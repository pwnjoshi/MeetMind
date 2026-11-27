import Foundation
import Speech
import AVFoundation
import CoreMedia

// MARK: - Shared plumbing

/// Carries the recorder's buffer stream into a detached task. `AVAudioPCMBuffer` is not
/// `Sendable`; the recorder hands out private copies, so crossing tasks is safe.
struct CaptionAudioSource: @unchecked Sendable {
    let stream: AsyncStream<AVAudioPCMBuffer>
}

/// Fans the recorder stream out to the active caption engines, and counts delivered audio so
/// every engine reports times relative to recording start. Each consumer uses its own slot
/// (slot 0 for single-engine sessions; English and Hindi use slots 0 and 1 together).
/// Slot 0 has a stream attached at creation so no audio is lost while an engine is chosen.
final class CaptionAudioRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [Int: AsyncStream<AVAudioPCMBuffer>.Continuation] = [:]
    private var initialStream: AsyncStream<AVAudioPCMBuffer>?
    private var delivered: TimeInterval = 0
    private var isFinished = false

    init() {
        let pair = AsyncStream<AVAudioPCMBuffer>.makeStream(of: AVAudioPCMBuffer.self,
                                                            bufferingPolicy: .bufferingNewest(2000))
        continuations[0] = pair.continuation
        initialStream = pair.stream
    }

    var deliveredSeconds: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return delivered
    }

    /// Returns a stream of audio from now on (the first call for slot 0 returns everything since
    /// the start) and the recording time at which it begins. A previous stream of the same slot
    /// is finished; other slots keep receiving audio.
    func attach(slot: Int = 0) -> (stream: AsyncStream<AVAudioPCMBuffer>, startOffset: TimeInterval) {
        lock.lock()
        if slot == 0, let initial = initialStream {
            initialStream = nil
            lock.unlock()
            return (initial, 0)
        }
        let pair = AsyncStream<AVAudioPCMBuffer>.makeStream(of: AVAudioPCMBuffer.self,
                                                            bufferingPolicy: .bufferingNewest(2000))
        let previous = continuations[slot]
        let offset = delivered
        if isFinished {
            pair.continuation.finish()
            continuations[slot] = nil
        } else {
            continuations[slot] = pair.continuation
        }
        lock.unlock()
        previous?.finish()
        return (pair.stream, offset)
    }

    /// Ends one consumer's stream so audio no longer queues for it.
    func release(slot: Int) {
        lock.lock()
        let previous = continuations.removeValue(forKey: slot)
        if slot == 0 { initialStream = nil }
        lock.unlock()
        previous?.finish()
    }

    /// Stops delivering audio to engines but keeps counting time.
    func detach() {
        lock.lock()
        let previous = Array(continuations.values)
        continuations.removeAll()
        initialStream = nil
        lock.unlock()
        for continuation in previous { continuation.finish() }
    }

    func send(_ buffer: AVAudioPCMBuffer) {
        let rate = buffer.format.sampleRate
        let duration = rate > 0 ? Double(buffer.frameLength) / rate : 0
        lock.lock()
        delivered += duration
        let targets = Array(continuations.values)
        lock.unlock()
        for target in targets { target.yield(buffer) }
    }

    func finish() {
        lock.lock()
        isFinished = true
        let previous = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in previous { continuation.finish() }
    }
}

/// Where an engine reports its captions. `CaptionAssembler` is the normal sink; in
/// code-switching sessions each language gets its own sink that feeds `CaptionLanguageHub`.
protocol CaptionResultSink: AnyObject, Sendable {
    func setAutoCommit(_ policy: LiveCaptionStitcher.AutoCommitPolicy?)
    func updateOpen(_ words: [CaptionWord])
    /// Removes the one mutable phrase without changing the committed prefix.
    func clearOpen()
    func commit(_ words: [CaptionWord])
    func notice(_ message: String)
}

/// Keeps existing lightweight/test sinks source-compatible. Production sinks that display an
/// open phrase implement this explicitly.
extension CaptionResultSink {
    func clearOpen() {}
}

/// Thread-safe front for `LiveCaptionStitcher`. Every caption leaves through here so
/// engines that run one after another (or overlap during a restart) share one history.
final class CaptionAssembler: @unchecked Sendable {
    private let lock = NSLock()
    private var stitcher = LiveCaptionStitcher()
    private let sink: @Sendable (LiveTranscriptChunk) -> Void

    init(sink: @escaping @Sendable (LiveTranscriptChunk) -> Void) {
        self.sink = sink
    }

    func setAutoCommit(_ policy: LiveCaptionStitcher.AutoCommitPolicy?) {
        lock.lock()
        stitcher.autoCommit = policy
        lock.unlock()
    }

    /// A partial (volatile) hypothesis.
    func updateOpen(_ words: [CaptionWord]) {
        lock.lock()
        defer { lock.unlock() }
        for chunk in stitcher.updateOpen(words) {
            sink(chunk)
        }
    }

    /// Explicitly removes the mutable tail. An empty non-final chunk is a semantic clear signal
    /// to consumers; it is never persisted as transcript content.
    func clearOpen() {
        lock.lock()
        stitcher.clearOpen()
        lock.unlock()
        sink(LiveTranscriptChunk(text: "", isFinal: false, segments: []))
    }

    /// A final result.
    func commit(_ words: [CaptionWord]) {
        lock.lock()
        let chunk = stitcher.commit(words)
        lock.unlock()
        if let chunk {
            sink(chunk)
        }
        clearOpen()
    }

    /// A status message shown in place of the live caption. It is never final, so it is
    /// not saved as transcript.
    func notice(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        sink(LiveTranscriptChunk(text: message, isFinal: false, segments: []))
    }
}

extension CaptionAssembler: CaptionResultSink {}

/// Converts recorder buffers to the format a speech module asks for.
final class CaptionAudioConverter {
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let input = buffer.format
        if input.sampleRate == outputFormat.sampleRate,
           input.channelCount == outputFormat.channelCount,
           input.commonFormat == outputFormat.commonFormat,
           input.isInterleaved == outputFormat.isInterleaved {
            return buffer
        }
        if converter == nil || converterInputFormat != input {
            converter = AVAudioConverter(from: input, to: outputFormat)
            converterInputFormat = input
        }
        guard let converter, input.sampleRate > 0 else { return nil }
        let ratio = outputFormat.sampleRate / input.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error || conversionError != nil || output.frameLength == 0 { return nil }
        return output
    }
}

// MARK: - SFSpeechRecognizer engine (iOS 17+, always on-device)

/// Live captions with `SFSpeechRecognizer`, on-device only. A request is replaced
/// shortly before the ~1 minute limit. The replacement starts from the last two seconds
/// of audio, so no word falls into the gap, and the old request is cut a second before
/// its end, so a word clipped by `endAudio` is never kept. `LiveCaptionStitcher` removes
/// whatever both requests heard.
final class SFSpeechCaptionEngine: @unchecked Sendable {
    private final class Slot {
        let id: Int
        let startOffset: TimeInterval
        let request: SFSpeechAudioBufferRecognitionRequest
        var task: SFSpeechRecognitionTask?
        var fed: TimeInterval = 0
        /// Recording time at which `endAudio` was sent. Nil while the slot still receives audio.
        var endedAt: TimeInterval?
        /// Words ending after this time are left to the next slot.
        var cutoff: TimeInterval?
        var finished = false
        var lastOpen: [CaptionWord] = []
        var heldFinals: [[CaptionWord]] = []
        var heldOpen: [CaptionWord]?

        init(id: Int, startOffset: TimeInterval, request: SFSpeechAudioBufferRecognitionRequest) {
            self.id = id
            self.startOffset = startOffset
            self.request = request
        }
    }

    private struct RingEntry {
        let buffer: AVAudioPCMBuffer
        let duration: TimeInterval
    }

    private let recognizer: SFSpeechRecognizer
    private let contextualStrings: [String]
    private let assembler: any CaptionResultSink
    private let rotateAfter: TimeInterval
    private let replaySeconds: TimeInterval
    private let handoverMargin: TimeInterval
    private let finalWaitSeconds: TimeInterval = 3.0

    private let lock = NSLock()
    private var slots: [Slot] = []
    private var ring: [RingEntry] = []
    private var ringDuration: TimeInterval = 0
    private var nextSlotID = 0
    private var clock: TimeInterval = 0
    private var lastSlotCreatedAt = Date.distantPast
    private var consecutiveFailures = 0
    private var fatalMessage: String?

    init(recognizer: SFSpeechRecognizer, contextualStrings: [String], assembler: any CaptionResultSink,
         rotateAfter: TimeInterval = 50, replaySeconds: TimeInterval = 2, handoverMargin: TimeInterval = 1) {
        self.recognizer = recognizer
        self.contextualStrings = contextualStrings
        self.assembler = assembler
        self.rotateAfter = rotateAfter
        self.replaySeconds = replaySeconds
        self.handoverMargin = handoverMargin
    }

    /// Consumes `audio` until it ends, then waits briefly for the last final result.
    func run(audio: AsyncStream<AVAudioPCMBuffer>, startOffset: TimeInterval) async throws {
        assembler.setAutoCommit(.captions)
        setClock(startOffset)

        for await buffer in audio {
            if Task.isCancelled { break }
            feed(buffer)
            if failureMessage != nil { break }
        }
        endAllAudio()
        for _ in 0..<30 {
            if hasNoSlots { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        discardRemainingSlots()

        if let message = failureMessage {
            throw SpeechTranscriptionError.recognitionRequestFailed(message)
        }
    }

    // MARK: Locked accessors (synchronous so they are safe to call from async code)

    private func setClock(_ value: TimeInterval) {
        lock.lock()
        clock = value
        lock.unlock()
    }

    private var failureMessage: String? {
        lock.lock()
        defer { lock.unlock() }
        return fatalMessage
    }

    private var hasNoSlots: Bool {
        lock.lock()
        defer { lock.unlock() }
        return slots.isEmpty
    }

    // MARK: Feeding

    private func feed(_ buffer: AVAudioPCMBuffer) {
        let rate = buffer.format.sampleRate
        guard rate > 0 else { return }
        let duration = Double(buffer.frameLength) / rate
        var abandoned: [Slot] = []

        lock.lock()
        // A request that never delivered its final result must not hold back its successor.
        if slots.count > 1, let first = slots.first, let endedAt = first.endedAt, clock - endedAt > finalWaitSeconds {
            commitLastOpen(of: first)
            abandoned.append(first)
            slots.removeFirst()
            promoteLocked()
        }

        if slots.isEmpty, Date().timeIntervalSince(lastSlotCreatedAt) >= 0.4 {
            slots.append(makeSlotLocked())
        }

        for slot in slots where slot.endedAt == nil {
            slot.request.append(buffer)
            slot.fed += duration
        }
        clock += duration
        ring.append(RingEntry(buffer: buffer, duration: duration))
        ringDuration += duration
        while ring.count > 1, ringDuration - ring[0].duration >= replaySeconds {
            ringDuration -= ring[0].duration
            ring.removeFirst()
        }

        if slots.count == 1, let current = slots.first, current.endedAt == nil, current.fed >= rotateAfter {
            current.request.endAudio()
            current.endedAt = clock
            current.cutoff = clock - handoverMargin
            slots.append(makeSlotLocked())
        }
        lock.unlock()

        for slot in abandoned { slot.task?.cancel() }
    }

    /// Must be called with `lock` held.
    private func makeSlotLocked() -> Slot {
        let id = nextSlotID
        nextSlotID += 1
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        // Privacy: the app is local-only. The caller only builds this engine when the
        // recognizer supports on-device recognition.
        request.requiresOnDeviceRecognition = true
        if !contextualStrings.isEmpty {
            request.contextualStrings = contextualStrings
        }

        let startOffset = clock - ringDuration
        let slot = Slot(id: id, startOffset: startOffset, request: request)
        for entry in ring {
            request.append(entry.buffer)
        }
        slot.fed = ringDuration
        slot.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.receive(slotID: id, result: result, error: error)
        }
        lastSlotCreatedAt = Date()
        return slot
    }

    // MARK: Results

    private func receive(slotID: Int, result: SFSpeechRecognitionResult?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else { return }
        let slot = slots[index]

        var words: [CaptionWord] = []
        if let result {
            words = result.bestTranscription.segments.map { segment in
                CaptionWord(text: segment.substring,
                            start: slot.startOffset + segment.timestamp,
                            end: slot.startOffset + segment.timestamp + segment.duration,
                            confidence: segment.confidence)
            }
        }
        let isFinal = result?.isFinal ?? false
        let finishing = isFinal || error != nil

        if !words.isEmpty {
            consecutiveFailures = 0
        } else if let error, !Self.isBenign(error) {
            consecutiveFailures += 1
            if consecutiveFailures >= 8 {
                fatalMessage = error.localizedDescription
            }
        }

        if !finishing {
            slot.lastOpen = words
            if index == 0 {
                assembler.updateOpen(Self.apply(cutoff: slot.cutoff, to: words))
            } else {
                slot.heldOpen = words
            }
            return
        }

        let finalWords = isFinal ? words : slot.lastOpen
        if index == 0 {
            assembler.commit(Self.apply(cutoff: slot.cutoff, to: finalWords))
            slot.finished = true
            slots.removeFirst()
            promoteLocked()
        } else {
            slot.heldFinals.append(finalWords)
            slot.heldOpen = nil
            slot.finished = true
        }
    }

    /// Releases what a successor slot produced while it waited behind the primary one.
    /// Must be called with `lock` held.
    private func promoteLocked() {
        while let first = slots.first {
            for batch in first.heldFinals {
                assembler.commit(Self.apply(cutoff: first.cutoff, to: batch))
            }
            first.heldFinals = []
            if first.finished {
                slots.removeFirst()
                continue
            }
            if let open = first.heldOpen {
                assembler.updateOpen(Self.apply(cutoff: first.cutoff, to: open))
                first.heldOpen = nil
            }
            break
        }
    }

    /// Must be called with `lock` held.
    private func commitLastOpen(of slot: Slot) {
        let words = Self.apply(cutoff: slot.cutoff, to: slot.lastOpen)
        if !words.isEmpty { assembler.commit(words) }
    }

    private static func apply(cutoff: TimeInterval?, to words: [CaptionWord]) -> [CaptionWord] {
        guard let cutoff else { return words }
        return words.filter { $0.end <= cutoff }
    }

    /// "No speech detected", "retry" and "request cancelled" are normal during silence or restarts.
    private static func isBenign(_ error: Error) -> Bool {
        let code = (error as NSError).code
        return code == 1110 || code == 203 || code == 216 || code == 301
    }

    // MARK: Shutdown

    /// Tells every open request that no more audio is coming so it delivers its final result.
    private func endAllAudio() {
        lock.lock()
        for slot in slots where slot.endedAt == nil {
            slot.request.endAudio()
            slot.endedAt = clock
        }
        lock.unlock()
    }

    /// Keeps the last partial text of requests that never finalized, then cancels them.
    private func discardRemainingSlots() {
        lock.lock()
        let remaining = slots
        for slot in remaining {
            commitLastOpen(of: slot)
        }
        slots.removeAll()
        lock.unlock()
        for slot in remaining { slot.task?.cancel() }
    }
}

// MARK: - SpeechAnalyzer engine (iOS 26+)

#if compiler(>=6.2)

/// Which iOS 26 transcriber to use for a locale.
@available(iOS 26.0, *)
struct ModernCaptionChoice: Sendable {
    enum Kind: Sendable {
        /// `SpeechTranscriber`: Apple's newest on-device model.
        case speech
        /// `DictationTranscriber`: the system dictation model. It covers more locales and older hardware.
        case dictation
    }

    let kind: Kind
    let locale: Locale
    let isInstalled: Bool
}

@available(iOS 26.0, *)
enum ModernCaptionResolver {
    /// First candidate locale that an iOS 26 transcriber supports, preferring `SpeechTranscriber`.
    /// Returns nil when neither supports any candidate, so the caller falls back to `SFSpeechRecognizer`.
    static func resolve(plan: LiveCaptionLocalePlan) async -> ModernCaptionChoice? {
        for identifier in plan.candidates {
            let requested = Locale(identifier: identifier)

            if SpeechTranscriber.isAvailable,
               let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
                let module = SpeechTranscriber(locale: supported,
                                               transcriptionOptions: [],
                                               reportingOptions: [.volatileResults],
                                               attributeOptions: [])
                if let installed = await installState(of: module) {
                    return ModernCaptionChoice(kind: .speech, locale: supported, isInstalled: installed)
                }
            }

            if let supported = await DictationTranscriber.supportedLocale(equivalentTo: requested) {
                let module = DictationTranscriber(locale: supported,
                                                  contentHints: [],
                                                  transcriptionOptions: [.punctuation],
                                                  reportingOptions: [.volatileResults, .frequentFinalization],
                                                  attributeOptions: [])
                if let installed = await installState(of: module) {
                    return ModernCaptionChoice(kind: .dictation, locale: supported, isInstalled: installed)
                }
            }
        }
        return nil
    }

    /// true = model installed, false = needs a download, nil = unsupported.
    private static func installState(of module: any SpeechModule) async -> Bool? {
        switch await AssetInventory.status(forModules: [module]) {
        case .installed: return true
        case .supported, .downloading: return false
        case .unsupported: return nil
        @unknown default: return nil
        }
    }
}

@available(iOS 26.0, *)
final class SpeechAnalyzerCaptionEngine: @unchecked Sendable {
    private let choice: ModernCaptionChoice
    private let contextualStrings: [String]
    private let assembler: any CaptionResultSink
    /// Confidence given to results that carry none: 1 for single-engine captions, 0 ("unknown")
    /// when two languages are being compared.
    private let unknownConfidence: Float

    init(choice: ModernCaptionChoice, contextualStrings: [String], assembler: any CaptionResultSink,
         unknownConfidence: Float = 1.0) {
        self.choice = choice
        self.contextualStrings = contextualStrings
        self.assembler = assembler
        self.unknownConfidence = unknownConfidence
    }

    /// Downloads the on-device model if needed. Returns true when it is installed afterwards.
    /// Uses only Apple's asset service; no audio leaves the device.
    static func installAssets(for choice: ModernCaptionChoice) async -> Bool {
        let module: any SpeechModule
        switch choice.kind {
        case .speech:
            module = SpeechTranscriber(locale: choice.locale, transcriptionOptions: [],
                                       reportingOptions: [.volatileResults], attributeOptions: [])
        case .dictation:
            module = DictationTranscriber(locale: choice.locale, contentHints: [],
                                          transcriptionOptions: [.punctuation],
                                          reportingOptions: [.volatileResults, .frequentFinalization],
                                          attributeOptions: [])
        }
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
        } catch {
            return false
        }
        return await AssetInventory.status(forModules: [module]) == .installed
    }

    /// Streams `audio` through a `SpeechAnalyzer` until it ends, then finalizes.
    func run(audio: AsyncStream<AVAudioPCMBuffer>, startOffset: TimeInterval) async throws {
        assembler.setAutoCommit(nil)
        let assembler = self.assembler
        let unknownConfidence = self.unknownConfidence

        let module: any SpeechModule
        let resultsTask: Task<Void, Error>
        switch choice.kind {
        case .speech:
            let transcriber = SpeechTranscriber(locale: choice.locale,
                                                transcriptionOptions: [],
                                                reportingOptions: [.volatileResults],
                                                attributeOptions: [.transcriptionConfidence])
            module = transcriber
            resultsTask = Task {
                for try await result in transcriber.results {
                    Self.deliver(text: result.text, range: result.range, isFinal: result.isFinal,
                                 offset: startOffset, unknownConfidence: unknownConfidence, assembler: assembler)
                }
            }
        case .dictation:
            let transcriber = DictationTranscriber(locale: choice.locale,
                                                   contentHints: [],
                                                   transcriptionOptions: [.punctuation],
                                                   reportingOptions: [.volatileResults, .frequentFinalization],
                                                   attributeOptions: [.transcriptionConfidence])
            module = transcriber
            resultsTask = Task {
                for try await result in transcriber.results {
                    Self.deliver(text: result.text, range: result.range, isFinal: result.isFinal,
                                 offset: startOffset, unknownConfidence: unknownConfidence, assembler: assembler)
                }
            }
        }

        // Keeps the model resident for the next recording. Failure is harmless.
        _ = try? await AssetInventory.reserve(locale: choice.locale)

        let analyzer = SpeechAnalyzer(modules: [module])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            resultsTask.cancel()
            throw SpeechTranscriptionError.recognizerUnavailable
        }
        if !contextualStrings.isEmpty {
            var context = AnalysisContext()
            context.contextualStrings[.general] = contextualStrings
            try? await analyzer.setContext(context)
        }

        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        do {
            try await analyzer.start(inputSequence: inputSequence)
        } catch {
            resultsTask.cancel()
            throw error
        }

        let converter = CaptionAudioConverter(outputFormat: format)
        for await buffer in audio {
            if Task.isCancelled { break }
            guard let converted = converter.convert(buffer) else { continue }
            inputBuilder.yield(AnalyzerInput(buffer: converted))
        }
        inputBuilder.finish()

        if Task.isCancelled {
            resultsTask.cancel()
            await analyzer.cancelAndFinishNow()
            return
        }
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            try await resultsTask.value
        } catch {
            resultsTask.cancel()
            throw error
        }
    }

    private static func deliver(text: AttributedString, range: CMTimeRange, isFinal: Bool,
                                offset: TimeInterval, unknownConfidence: Float, assembler: any CaptionResultSink) {
        let plain = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }
        let rawStart = range.start.seconds
        let rawEnd = range.end.seconds
        let start = (rawStart.isFinite ? rawStart : 0) + offset
        let end = (rawEnd.isFinite ? rawEnd : rawStart.isFinite ? rawStart : 0) + offset
        let confidence = Self.confidence(of: text) ?? unknownConfidence
        let words = CaptionWord.words(from: plain, start: start, end: max(start, end), confidence: confidence)
        if isFinal {
            assembler.commit(words)
        } else {
            assembler.updateOpen(words)
        }
    }

    /// Character-weighted mean of the per-run transcription confidence, nil when none is attached.
    private static func confidence(of text: AttributedString) -> Float? {
        var weighted = 0.0
        var weight = 0.0
        for run in text.runs {
            guard let value = run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] else { continue }
            let length = Double(max(1, text[run.range].characters.count))
            weighted += Double(value) * length
            weight += length
        }
        guard weight > 0 else { return nil }
        return Float(min(1, max(0, weighted / weight)))
    }
}

#endif
