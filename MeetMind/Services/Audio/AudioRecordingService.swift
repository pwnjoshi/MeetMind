import Foundation
import AVFoundation

public final class AudioRecordingService: NSObject, AudioRecordingServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let bitRate: Int
    private let noiseSuppression: Bool
    private var internalState: RecordingState = .idle
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var destinationFileURL: URL?
    private var writeFailure: String?
    
    private var recordingStartTime: Date?
    private var accumulatedDuration: TimeInterval = 0.0
    private var lastPauseTime: Date?
    
    private var meterContinuation: AsyncStream<Float>.Continuation?
    // Both live captions and the rolling offline preprocessor consume audio.
    // A single continuation made the most recently-subscribed consumer silently
    // disconnect the other one, which is why captions could disappear as soon as
    // background preparation started.
    private var bufferContinuations: [UUID: AsyncStream<AVAudioPCMBuffer>.Continuation] = [:]
    public var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation in
            let id = UUID()
            lock.lock()
            bufferContinuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.bufferContinuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }
    private var lastMeterYieldTime: Date = Date.distantPast
    
    public var state: RecordingState {
        lock.lock()
        defer { lock.unlock() }
        return internalState
    }
    
    public var currentDuration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard internalState == .recording, let startTime = recordingStartTime else {
            return accumulatedDuration
        }
        return accumulatedDuration + Date().timeIntervalSince(startTime)
    }
    
    public var audioMeterStream: AsyncStream<Float> {
        AsyncStream { continuation in
            self.lock.lock()
            self.meterContinuation = continuation
            self.lock.unlock()
            
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.meterContinuation = nil
                self?.lock.unlock()
            }
        }
    }
    
    public init(bitRate: Int = 128_000, noiseSuppression: Bool = false) {
        self.bitRate = bitRate
        self.noiseSuppression = noiseSuppression
        super.init()
    }
    
    deinit {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        meterContinuation?.finish()
        let continuations = bufferContinuations.values
        continuations.forEach { $0.finish() }
    }
    
    public func startRecording(destinationURL: URL) async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw AudioRecordingError.permissionDenied
        }
        lock.lock()
        guard internalState == .idle || internalState == .stopped else {
            let currentState = internalState
            lock.unlock()
            throw AudioRecordingError.invalidState("Cannot start recording in state: \(currentState)")
        }
        internalState = .preparing
        writeFailure = nil
        self.destinationFileURL = destinationURL
        self.accumulatedDuration = 0.0
        lock.unlock()
        
        // 1. Configure AVAudioSession
        let session = AVAudioSession.sharedInstance()
        var didStart = false
        defer {
            if !didStart {
                lock.lock()
                internalState = .idle
                lock.unlock()
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetooth, .defaultToSpeaker, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            lock.lock()
            internalState = .idle
            lock.unlock()
            throw AudioRecordingError.audioSessionSetupFailed(error.localizedDescription)
        }
        
        // 2. Configure AVAudioEngine and File
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        if noiseSuppression { try inputNode.setVoiceProcessingEnabled(true) }
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            lock.lock()
            internalState = .idle
            lock.unlock()
            throw AudioRecordingError.inputNodeUnavailable
        }
        
        // Adaptively handle input hardware format sample rates (e.g. 48kHz tap vs 44.1kHz default)
        let hardwareSampleRate = inputFormat.sampleRate > 0 ? inputFormat.sampleRate : 44100.0
        let channelCount = inputFormat.channelCount
        
        let fileSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: hardwareSampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: bitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        let file: AVAudioFile
        do {
            file = try AVAudioFile(
                forWriting: destinationURL,
                settings: fileSettings,
                commonFormat: inputFormat.commonFormat,
                interleaved: inputFormat.isInterleaved
            )
        } catch {
            lock.lock()
            internalState = .idle
            lock.unlock()
            throw AudioRecordingError.fileCreationFailed(error.localizedDescription)
        }
        
        // 3. Install Audio Tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            self.processAudioBuffer(buffer, targetFile: file)
        }
        
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            lock.lock()
            internalState = .idle
            lock.unlock()
            throw AudioRecordingError.engineStartFailed(error.localizedDescription)
        }
        
        lock.lock()
        self.audioEngine = engine
        self.audioFile = file
        self.recordingStartTime = Date()
        self.internalState = .recording
        didStart = true
        lock.unlock()
    }
    
    public func pauseRecording() throws {
        lock.lock()
        defer { lock.unlock() }
        guard internalState == .recording else {
            throw AudioRecordingError.invalidState("Cannot pause from state: \(internalState)")
        }
        if let start = recordingStartTime {
            accumulatedDuration += Date().timeIntervalSince(start)
            recordingStartTime = nil
        }
        lastPauseTime = Date()
        internalState = .paused
        meterContinuation?.yield(0.0)
    }
    
    public func resumeRecording() throws {
        lock.lock()
        defer { lock.unlock() }
        guard internalState == .paused else {
            throw AudioRecordingError.invalidState("Cannot resume from state: \(internalState)")
        }
        recordingStartTime = Date()
        lastPauseTime = nil
        internalState = .recording
    }
    
    public func stopRecording() async throws -> URL {
        lock.lock()
        guard internalState == .recording || internalState == .paused else {
            let currentState = internalState
            lock.unlock()
            throw AudioRecordingError.invalidState("Cannot stop recording from state: \(currentState)")
        }
        if let start = recordingStartTime {
            accumulatedDuration += Date().timeIntervalSince(start)
            recordingStartTime = nil
        }
        let engine = self.audioEngine
        let url = self.destinationFileURL
        let failure = self.writeFailure
        self.audioEngine = nil
        self.audioFile = nil
        self.internalState = .stopped
        lock.unlock()
        
        if let engine = engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        meterContinuation?.yield(0.0)
        meterContinuation?.finish()
        finishBufferStreams()
        
        guard let finalURL = url else {
            throw AudioRecordingError.recordingFailed("Destination URL was missing.")
        }
        if let failure { throw AudioRecordingError.recordingFailed(failure) }
        return finalURL
    }
    
    public func cancelRecording() throws {
        lock.lock()
        let engine = self.audioEngine
        let url = self.destinationFileURL
        self.audioEngine = nil
        self.audioFile = nil
        self.internalState = .idle
        self.accumulatedDuration = 0.0
        self.recordingStartTime = nil
        lock.unlock()
        
        if let engine = engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        meterContinuation?.yield(0.0)
        meterContinuation?.finish()
        finishBufferStreams()
        
        if let url = url, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, targetFile: AVAudioFile) {
        lock.lock()
        let currentState = internalState
        let meter = meterContinuation
        lock.unlock()
        guard currentState == .recording else { return }
        
        // Write audio frame
        do { try targetFile.write(from: buffer) }
        catch {
            lock.lock()
            writeFailure = error.localizedDescription
            lock.unlock()
            return
        }

        // Audio engine owns and reuses tap buffers. Copy before asynchronous recognition.
        lock.lock()
        let speechContinuations = Array(bufferContinuations.values)
        lock.unlock()
        if !speechContinuations.isEmpty,
           let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) {
            copy.frameLength = buffer.frameLength
            let sourceBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for index in 0..<sourceBuffers.count {
                if let source = sourceBuffers[index].mData, let destination = destinationBuffers[index].mData {
                    memcpy(destination, source, Int(sourceBuffers[index].mDataByteSize))
                }
            }
            speechContinuations.forEach { $0.yield(copy) }
        }
        
        // 60Hz Power Metering Calculation
        let now = Date()
        guard now.timeIntervalSince(lastMeterYieldTime) >= 0.016 else { return }
        lastMeterYieldTime = now
        
        guard let channelData = buffer.floatChannelData else { return }
        let channelSamples = channelData.pointee
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        
        var sumSquares: Float = 0.0
        var validSampleCount: Int = 0
        for i in 0..<frameLength {
            let sample = channelSamples[i]
            if sample.isFinite {
                sumSquares += sample * sample
                validSampleCount += 1
            }
        }
        guard validSampleCount > 0 else {
            meter?.yield(0.0)
            return
        }
        let rms = sqrt(sumSquares / Float(validSampleCount))
        guard rms.isFinite else {
            meter?.yield(0.0)
            return
        }
        let db = 20.0 * log10(max(rms, 0.0001))
        guard db.isFinite else {
            meter?.yield(0.0)
            return
        }
        
        // Map dB (-60 dB silence to 0 dB full scale) to linear [0.0, 1.0]
        let minDb: Float = -60.0
        let clampedDb = max(minDb, min(0.0, db))
        let linearPower = (clampedDb - minDb) / (0.0 - minDb)
        let finalPower = linearPower.isFinite ? max(0.0, min(1.0, linearPower)) : 0.0
        
        meter?.yield(finalPower)
    }

    private func finishBufferStreams() {
        lock.lock()
        let continuations = Array(bufferContinuations.values)
        bufferContinuations.removeAll()
        lock.unlock()
        continuations.forEach { $0.finish() }
    }
}
