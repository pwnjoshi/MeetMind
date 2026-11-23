import Foundation
import AVFoundation
import Speech
import Observation

// Vidur's voice: on-device speech to text (SFSpeechRecognizer with requiresOnDeviceRecognition) and
// spoken replies (AVSpeechSynthesizer). Audio never leaves the iPhone. Nothing here runs while a
// meeting is being recorded; the callers check AppState.isRecordingActive.

enum VidurVoiceSettings {
    static let voiceRepliesKey = "Manent_Vidur_VoiceReplies"
    static let heyVidurKey = "Manent_Vidur_HeyVidur"
    static let recordingPausedMessage = "Vidur\u{2019}s voice is paused while recording"

    /// Locales to try, best first. Hindi and Hinglish users get hi-IN, everyone else en-IN.
    static func recognitionLocales() -> [Locale] {
        let saved = UserDefaults.standard.string(forKey: "MeetMind_SavedRecordingLanguage") ?? "hinglish"
        let hindi = saved == "hinglish" || saved == "hindi"
        let identifiers = hindi ? ["hi-IN", "en-IN", "en-US"] : ["en-IN", "en-US"]
        return identifiers.map { Locale(identifier: $0) }
    }
}

enum VidurVoiceError: Error {
    case noMicrophone
}

enum VidurPermissions {
    /// Asks for speech recognition and microphone access, one after the other.
    static func requestAll() async -> Bool {
        let speech: Bool = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// True once both permissions were granted. Never prompts.
    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVAudioApplication.shared.recordPermission == .granted
    }

    /// The first recognizer that can work fully on this iPhone. Nil means voice input is unavailable,
    /// because Vidur never falls back to a server.
    static func onDeviceRecognizer(locales: [Locale]) -> SFSpeechRecognizer? {
        for locale in locales {
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable,
               recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }
        return nil
    }
}

enum VidurAudioSession {
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: [])
    }

    static func activateForListening() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
        try session.setActive(true, options: [])
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Audio and recognizer callbacks run on system queues, so they are built outside any actor.
enum VidurMicTap {
    static func install(on node: AVAudioInputNode, format: AVAudioFormat, request: SFSpeechAudioBufferRecognitionRequest) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    static func startTask(recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest,
                          handler: @escaping @Sendable (String?, Bool, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }
}

// MARK: - Dictation

/// Listens once, shows live partial text and finishes after a short silence.
@MainActor
@Observable
final class VidurDictation {
    private(set) var isListening = false
    private(set) var partialText = ""
    private(set) var errorMessage: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTask: Task<Void, Never>?
    @ObservationIgnored private var onFinish: ((String) -> Void)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var silenceSeconds: TimeInterval = 1.6

    /// Starts listening. `onFinish` gets the final text, or an empty string when the user said nothing.
    func start(silenceSeconds: TimeInterval = 1.6, initialTimeout: TimeInterval = 9,
               onFinish: @escaping (String) -> Void) async {
        guard !isListening else { return }
        errorMessage = nil
        partialText = ""
        guard await VidurPermissions.requestAll() else {
            errorMessage = "Allow microphone and speech access in Settings to talk to Vidur."
            onFinish("")
            return
        }
        guard !isListening else { return }
        guard let recognizer = VidurPermissions.onDeviceRecognizer(locales: VidurVoiceSettings.recognitionLocales()) else {
            errorMessage = "On-device speech recognition isn\u{2019}t available for your language. Vidur never sends audio to a server, so voice input is off."
            onFinish("")
            return
        }
        self.onFinish = onFinish
        self.silenceSeconds = silenceSeconds
        generation += 1
        let current = generation
        do {
            try VidurAudioSession.activate()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            request.addsPunctuation = true
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw VidurVoiceError.noMicrophone }
            VidurMicTap.install(on: input, format: format, request: request)
            engine.prepare()
            try engine.start()
            self.request = request
            task = VidurMicTap.startTask(recognizer: recognizer, request: request) { [weak self] text, isFinal, failed in
                Task { @MainActor in
                    self?.handle(text: text, isFinal: isFinal, failed: failed, generation: current)
                }
            }
            isListening = true
            scheduleSilence(after: initialTimeout, generation: current)
        } catch {
            cleanUp()
            errorMessage = "I couldn\u{2019}t start the microphone. Try again in a moment."
            let callback = self.onFinish
            self.onFinish = nil
            callback?("")
        }
    }

    /// Stops listening and discards what was heard.
    func cancel() {
        onFinish = nil
        cleanUp()
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool, generation gen: Int) {
        guard gen == generation, isListening else { return }
        if let text, !text.isEmpty, text != partialText {
            partialText = text
            scheduleSilence(after: silenceSeconds, generation: gen)
        }
        if isFinal || failed { finish() }
    }

    private func scheduleSilence(after seconds: TimeInterval, generation gen: Int) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.silenceElapsed(generation: gen)
        }
    }

    private func silenceElapsed(generation gen: Int) {
        guard gen == generation, isListening else { return }
        finish()
    }

    private func finish() {
        let text = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        let callback = onFinish
        onFinish = nil
        cleanUp()
        callback?(text)
    }

    private func cleanUp() {
        silenceTask?.cancel()
        silenceTask = nil
        generation += 1
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        let wasListening = isListening
        isListening = false
        if wasListening { VidurAudioSession.deactivate() }
    }
}

// MARK: - Speaking

/// Reads replies aloud with the best installed en-IN or hi-IN voice (Premium, then Enhanced, then standard).
@MainActor
final class VidurSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = VidurSpeaker()

    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()
    private var current: AVSpeechUtterance?
    private var onFinish: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, onFinish: (() -> Void)? = nil) {
        stop()
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { onFinish?(); return }
        do {
            try VidurAudioSession.activate()
        } catch {
            onFinish?()
            return
        }
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = Self.bestVoice(for: cleaned)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.05
        current = utterance
        self.onFinish = onFinish
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Stops at once, for example when the user taps or starts talking.
    func stop() {
        current = nil
        onFinish = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        if isSpeaking {
            isSpeaking = false
            VidurAudioSession.deactivate()
        }
    }

    static func bestVoice(for text: String) -> AVSpeechSynthesisVoice? {
        let hasDevanagari = text.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
        let language = hasDevanagari ? "hi-IN" : "en-IN"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        if let best = voices.max(by: { $0.quality.rawValue < $1.quality.rawValue }) { return best }
        return AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(identifier) }
    }

    private func finished(_ identifier: ObjectIdentifier) {
        guard let current, ObjectIdentifier(current) == identifier else { return }
        let callback = onFinish
        self.current = nil
        onFinish = nil
        isSpeaking = false
        VidurAudioSession.deactivate()
        callback?()
    }
}

// MARK: - Shared state between the wake-word listener and the Vidur sheet

struct VidurWakeRequest: Equatable {
    /// What was said after "Hey Vidur". Empty means Vidur should listen for the request.
    let text: String
}

@MainActor
@Observable
final class VidurVoiceCoordinator {
    static let shared = VidurVoiceCoordinator()
    /// True while any Vidur sheet is on screen. The wake-word listener pauses so the sheet can use the microphone.
    var isSheetOpen = false
    var pendingWake: VidurWakeRequest?

    func consumeWake() -> VidurWakeRequest? {
        defer { pendingWake = nil }
        return pendingWake
    }
}
