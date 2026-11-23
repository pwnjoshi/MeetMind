import Foundation
import Speech
import AVFoundation

/// Live captions and file transcription, always on-device.
///
/// Live path (`startLiveTranscription`):
/// - iOS 26+: `SpeechAnalyzer` with `SpeechTranscriber`, or `DictationTranscriber` for locales
///   the first does not cover, fed with volatile and final results.
/// - iOS 17-25, or when iOS 26 has no model for the locale: `SFSpeechRecognizer` with
///   `requiresOnDeviceRecognition`, restarted seamlessly before its request time limit.
/// - If neither can run on-device, the stream shows a truthful notice instead of using a server.
///
/// The language comes from the saved recording language (`MeetMind_SavedRecordingLanguage`):
/// English uses `en-IN` then `en-US`, Hindi uses `hi-IN`. Hinglish and Automatic run an English
/// and a Hindi recognizer together and show each phrase in the language that was spoken
/// (`LiveCaptionLanguageArbiter`, `CaptionLanguageHub`); if only one is available on the device,
/// that one runs alone.
public final class SpeechTranscriptionService: SpeechTranscriptionServiceProtocol, @unchecked Sendable {
    private let speechRecognizer: SFSpeechRecognizer?
    private let preferredLocaleIdentifier: String
    private let userDefaults: UserDefaults
    private let onDeviceOnly = true
    private var activeRecognitionTask: SFSpeechRecognitionTask?
    private var activeSession: LiveCaptionSession?
    private var activeSessionTask: Task<Void, Never>?
    private var storedContextualStrings: [String] = []
    private let lock = NSLock()

    /// Names and terms that help recognizers (participants, agenda words). Set before
    /// `startLiveTranscription`; build the list with `LiveCaptionContext.contextualStrings`.
    public var contextualStrings: [String] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedContextualStrings
        }
        set {
            lock.lock()
            storedContextualStrings = newValue
            lock.unlock()
        }
    }

    public var isAvailable: Bool {
        if speechRecognizer?.isAvailable == true { return true }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return SpeechTranscriber.isAvailable }
        #endif
        return false
    }

    public var supportsOnDeviceRecognition: Bool {
        if speechRecognizer?.supportsOnDeviceRecognition == true { return true }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return SpeechTranscriber.isAvailable }
        #endif
        return false
    }

    public init(locale: Locale = Locale(identifier: "en-US"), userDefaults: UserDefaults = .standard) {
        self.preferredLocaleIdentifier = locale.identifier
        self.userDefaults = userDefaults
        let plan = LiveCaptionLocalePlanner.plan(language: LiveCaptionLanguage.stored(in: userDefaults),
                                                 preferredLocaleIdentifier: locale.identifier)
        let primary = plan.candidates.first.map { Locale(identifier: $0) } ?? locale
        self.speechRecognizer = SFSpeechRecognizer(locale: primary) ?? SFSpeechRecognizer(locale: locale)
    }

    deinit {
        stopLiveTranscription()
    }

    public func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Downloads the on-device live caption model for the current language if it is missing.
    /// Call this while the user is not recording (for example when changing the language).
    /// Returns true when live captions can run on-device afterwards.
    public func prepareLiveCaptionModels() async -> Bool {
        let language = LiveCaptionLanguage.stored(in: userDefaults)
        if let dual = LiveCaptionLocalePlanner.dualPlan(language: language,
                                                        preferredLocaleIdentifier: preferredLocaleIdentifier) {
            // Code-switching needs both models; captions still work when only one is available.
            let hindiReady = await prepareModels(for: dual.hindi)
            let englishReady = await prepareModels(for: dual.english)
            return hindiReady || englishReady
        }
        let plan = LiveCaptionLocalePlanner.plan(language: language,
                                                 preferredLocaleIdentifier: preferredLocaleIdentifier)
        return await prepareModels(for: plan)
    }

    private func prepareModels(for plan: LiveCaptionLocalePlan) async -> Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), let choice = await ModernCaptionResolver.resolve(plan: plan) {
            if choice.isInstalled { return true }
            if await SpeechAnalyzerCaptionEngine.installAssets(for: choice) { return true }
        }
        #endif
        return LiveCaptionSession.makeOnDeviceRecognizer(candidates: plan.candidates) != nil
    }

    public func startLiveTranscription(audioBufferStream: AsyncStream<AVAudioPCMBuffer>) -> AsyncThrowingStream<LiveTranscriptChunk, Error> {
        let configuration = LiveCaptionSession.Configuration(
            language: LiveCaptionLanguage.stored(in: userDefaults),
            preferredLocaleIdentifier: preferredLocaleIdentifier,
            contextualStrings: contextualStrings
        )
        let source = CaptionAudioSource(stream: audioBufferStream)

        return AsyncThrowingStream { continuation in
            let session = LiveCaptionSession(configuration: configuration)
            let task = Task(priority: .userInitiated) {
                await session.run(source: source) { chunk in
                    _ = continuation.yield(chunk)
                }
                continuation.finish()
            }

            self.lock.lock()
            let previousSession = self.activeSession
            let previousTask = self.activeSessionTask
            self.activeSession = session
            self.activeSessionTask = task
            self.lock.unlock()
            previousSession?.stop()
            previousTask?.cancel()

            continuation.onTermination = { @Sendable _ in
                session.stop()
                task.cancel()
            }
        }
    }

    public func stopLiveTranscription() {
        lock.lock()
        let session = activeSession
        let task = activeSessionTask
        let fileTask = activeRecognitionTask
        activeSession = nil
        activeSessionTask = nil
        activeRecognitionTask = nil
        lock.unlock()
        session?.stop()
        task?.cancel()
        fileTask?.cancel()
    }

    public func transcribeAudioFile(at url: URL) async throws -> [LiveTranscriptSegment] {
        guard await requestAuthorization() == .authorized else {
            throw SpeechTranscriptionError.authorizationDenied
        }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SpeechTranscriptionError.audioFileReadFailed("File not found at \(url.path)")
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        if onDeviceOnly {
            guard recognizer.supportsOnDeviceRecognition else {
                throw SpeechTranscriptionError.onDeviceRecognitionUnavailable
            }
            request.requiresOnDeviceRecognition = true
        }
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { continuation in
            let continuationLock = NSLock()
            var hasResumed = false

            @Sendable func resumeOnce(with result: Result<[LiveTranscriptSegment], Error>) {
                continuationLock.lock()
                defer { continuationLock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(with: result)
            }

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    resumeOnce(with: .failure(SpeechTranscriptionError.recognitionRequestFailed(error.localizedDescription)))
                    return
                }
                guard let result = result, result.isFinal else { return }

                let segments = result.bestTranscription.segments.map { seg in
                    LiveTranscriptSegment(
                        text: seg.substring,
                        startTime: seg.timestamp,
                        duration: seg.duration,
                        confidence: seg.confidence
                    )
                }
                resumeOnce(with: .success(segments))
            }
            lock.lock()
            activeRecognitionTask = task
            lock.unlock()
        }
    }
}

// MARK: - Live caption session

/// One live caption run: picks the engine for the language, feeds it the recorder's audio,
/// and reports captions through the assembler.
final class LiveCaptionSession: @unchecked Sendable {
    struct Configuration: Sendable {
        let language: LiveCaptionLanguage
        let preferredLocaleIdentifier: String
        let contextualStrings: [String]
    }

    private let configuration: Configuration
    private let router = CaptionAudioRouter()
    private let lock = NSLock()
    private var pumpTask: Task<Void, Never>?
    private var isStopped = false

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func stop() {
        lock.lock()
        isStopped = true
        let pump = pumpTask
        lock.unlock()
        pump?.cancel()
        router.finish()
    }

    /// Stores the pump task. Returns true when the session was already stopped.
    private func registerPump(_ pump: Task<Void, Never>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pumpTask = pump
        return isStopped
    }

    /// Returns when the audio ends (recording stopped), the session is stopped, or no
    /// on-device engine is available. Failures become a notice; they never use a server.
    func run(source: CaptionAudioSource, emit: @escaping @Sendable (LiveTranscriptChunk) -> Void) async {
        var plan = LiveCaptionLocalePlanner.plan(language: configuration.language,
                                                 preferredLocaleIdentifier: configuration.preferredLocaleIdentifier)
        let assembler = CaptionAssembler(sink: emit)
        let router = self.router

        let pump = Task(priority: .userInitiated) {
            for await buffer in source.stream {
                if Task.isCancelled { break }
                router.send(buffer)
            }
            router.finish()
        }
        if registerPump(pump) {
            pump.cancel()
            router.finish()
        }
        defer {
            pump.cancel()
            router.finish()
        }

        // Hinglish and Automatic: an English and a Hindi recognizer hear the same audio and the
        // arbiter picks the language of each phrase. If only one language can run, it runs alone.
        if let dual = LiveCaptionLocalePlanner.dualPlan(language: configuration.language,
                                                        preferredLocaleIdentifier: configuration.preferredLocaleIdentifier) {
            switch await prepareDual(dual) {
            case .dual(let english, let hindi, let hindiAudio):
                await runDual(plan: dual, english: english, hindi: hindi, hindiAudio: hindiAudio, assembler: assembler)
                return
            case .single(let chosen):
                plan = chosen
            }
        }

        let recognizer = Self.makeOnDeviceRecognizer(candidates: plan.candidates)

        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if await runModern(plan: plan, recognizer: recognizer, assembler: assembler) { return }
        }
        #endif

        await runSFSpeech(plan: plan, recognizer: recognizer, assembler: assembler)
    }

    // MARK: Code-switching (English + Hindi)

    /// What one language needs to run: an on-device recognizer and/or an installed iOS 26 model.
    struct CaptionChannelSetup: @unchecked Sendable {
        let recognizer: SFSpeechRecognizer?
        /// A `ModernCaptionChoice` (iOS 26). Stored type-erased because the type is iOS 26 only.
        let modernChoice: (any Sendable)?
        let modernInstalled: Bool
        let modernNeedsDownload: Bool

        var isReady: Bool { modernInstalled || recognizer != nil }
    }

    struct CaptionChannelInput: @unchecked Sendable {
        let setup: CaptionChannelSetup
        let sink: CaptionChannelSink
        let slot: Int
        let audio: AsyncStream<AVAudioPCMBuffer>
        let startOffset: TimeInterval
    }

    enum DualPreparation {
        case dual(english: CaptionChannelSetup, hindi: CaptionChannelSetup, hindiAudio: CaptionAudioStreamHandle)
        case single(LiveCaptionLocalePlan)
    }

    /// Hindi's audio stream, attached before the models are resolved so no audio is lost.
    struct CaptionAudioStreamHandle: @unchecked Sendable {
        let stream: AsyncStream<AVAudioPCMBuffer>
        let startOffset: TimeInterval
    }

    private func prepareDual(_ dual: LiveCaptionDualPlan) async -> DualPreparation {
        let hindiSlot = router.attach(slot: 1)
        let english = await Self.makeSetup(plan: dual.english)
        let hindi = await Self.makeSetup(plan: dual.hindi)

        if english.isReady && hindi.isReady {
            Self.installInBackground(english)
            Self.installInBackground(hindi)
            return .dual(english: english, hindi: hindi,
                         hindiAudio: CaptionAudioStreamHandle(stream: hindiSlot.stream, startOffset: hindiSlot.startOffset))
        }

        // One language only. Hindi is the app default, so it also carries the "downloading" and
        // "unavailable" notices of the single-engine path when neither language is ready.
        router.release(slot: 1)
        if english.isReady && !hindi.isReady {
            Self.installInBackground(hindi)
            return .single(dual.english)
        }
        if hindi.isReady {
            Self.installInBackground(english)
        }
        return .single(dual.hindi)
    }

    private static func makeSetup(plan: LiveCaptionLocalePlan) async -> CaptionChannelSetup {
        let recognizer = makeOnDeviceRecognizer(candidates: plan.candidates)
        var choice: (any Sendable)?
        var installed = false
        var needsDownload = false
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), let resolved = await ModernCaptionResolver.resolve(plan: plan) {
            choice = resolved
            installed = resolved.isInstalled
            needsDownload = !resolved.isInstalled
        }
        #endif
        return CaptionChannelSetup(recognizer: recognizer, modernChoice: choice,
                                   modernInstalled: installed, modernNeedsDownload: needsDownload)
    }

    /// Starts a model download for the next recording. Never blocks or affects this session.
    private static func installInBackground(_ setup: CaptionChannelSetup) {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), setup.modernNeedsDownload,
           let choice = setup.modernChoice as? ModernCaptionChoice {
            Task.detached(priority: .utility) {
                _ = await SpeechAnalyzerCaptionEngine.installAssets(for: choice)
            }
        }
        #endif
    }

    private func runDual(plan: LiveCaptionDualPlan, english: CaptionChannelSetup, hindi: CaptionChannelSetup,
                         hindiAudio: CaptionAudioStreamHandle, assembler: CaptionAssembler) async {
        let hub = CaptionLanguageHub(downstream: assembler)
        let englishAudio = router.attach(slot: 0)
        let englishInput = CaptionChannelInput(setup: english, sink: hub.sink(for: .english), slot: 0,
                                               audio: englishAudio.stream, startOffset: englishAudio.startOffset)
        let hindiInput = CaptionChannelInput(setup: hindi, sink: hub.sink(for: .hindi), slot: 1,
                                             audio: hindiAudio.stream, startOffset: hindiAudio.startOffset)

        let outcomes: [Bool] = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            group.addTask { await self.runChannel(englishInput) }
            group.addTask { await self.runChannel(hindiInput) }
            var results: [Bool] = []
            for await outcome in group { results.append(outcome) }
            return results
        }
        hub.finish()
        if !Task.isCancelled, !outcomes.contains(true) {
            assembler.notice(LiveCaptionNotice.unavailable(languageName: "Hindi and English"))
        }
    }

    /// Runs one language to the end of the audio. Returns false when its recognizer failed, in
    /// which case the hub carries on with the other language alone.
    private func runChannel(_ input: CaptionChannelInput) async -> Bool {
        defer { input.sink.end() }
        var audio = input.audio
        var startOffset = input.startOffset

        #if compiler(>=6.2)
        if #available(iOS 26.0, *), input.setup.modernInstalled,
           let choice = input.setup.modernChoice as? ModernCaptionChoice {
            let engine = SpeechAnalyzerCaptionEngine(choice: choice,
                                                     contextualStrings: configuration.contextualStrings,
                                                     assembler: input.sink,
                                                     unknownConfidence: 0)
            do {
                try await engine.run(audio: audio, startOffset: startOffset)
                return true
            } catch {
                if Task.isCancelled { return true }
                guard input.setup.recognizer != nil else { return false }
                // Continue this language on the older recognizer from the current audio position.
                let next = router.attach(slot: input.slot)
                audio = next.stream
                startOffset = next.startOffset
            }
        }
        #endif

        guard let recognizer = input.setup.recognizer else { return false }
        let engine = SFSpeechCaptionEngine(recognizer: recognizer,
                                           contextualStrings: configuration.contextualStrings,
                                           assembler: input.sink)
        do {
            try await engine.run(audio: audio, startOffset: startOffset)
            return true
        } catch {
            return Task.isCancelled
        }
    }

    // MARK: Engines

    private func runSFSpeech(plan: LiveCaptionLocalePlan, recognizer: SFSpeechRecognizer?, assembler: CaptionAssembler) async {
        guard let recognizer else {
            assembler.notice(LiveCaptionNotice.unavailable(languageName: plan.languageName))
            return
        }
        let (audio, offset) = router.attach()
        let engine = SFSpeechCaptionEngine(recognizer: recognizer,
                                           contextualStrings: configuration.contextualStrings,
                                           assembler: assembler)
        do {
            try await engine.run(audio: audio, startOffset: offset)
        } catch {
            guard !Task.isCancelled else { return }
            assembler.notice(LiveCaptionNotice.unavailable(languageName: plan.languageName))
        }
    }

    #if compiler(>=6.2)
    /// Returns true when the iOS 26 engine handled the session (including a notice), false
    /// when the caller should use `SFSpeechRecognizer`.
    @available(iOS 26.0, *)
    private func runModern(plan: LiveCaptionLocalePlan, recognizer: SFSpeechRecognizer?, assembler: CaptionAssembler) async -> Bool {
        guard let choice = await ModernCaptionResolver.resolve(plan: plan) else { return false }
        let engine = SpeechAnalyzerCaptionEngine(choice: choice,
                                                 contextualStrings: configuration.contextualStrings,
                                                 assembler: assembler)

        if choice.isInstalled {
            let (audio, offset) = router.attach()
            do {
                try await engine.run(audio: audio, startOffset: offset)
                return true
            } catch {
                // Cancelled sessions are done. Any other failure falls back to SFSpeechRecognizer.
                return Task.isCancelled
            }
        }

        // The model must be downloaded. Recording and captions must not wait for it: use the
        // older on-device recognizer meanwhile and switch when the model is ready.
        assembler.notice(LiveCaptionNotice.downloading(languageName: plan.languageName))
        var stopgap: Task<Void, Never>?
        if let recognizer {
            let (audio, offset) = router.attach()
            let stopgapEngine = SFSpeechCaptionEngine(recognizer: recognizer,
                                                      contextualStrings: configuration.contextualStrings,
                                                      assembler: assembler)
            stopgap = Task(priority: .userInitiated) {
                try? await stopgapEngine.run(audio: audio, startOffset: offset)
            }
        } else {
            router.detach()
        }

        let installed = await SpeechAnalyzerCaptionEngine.installAssets(for: choice)
        if Task.isCancelled {
            stopgap?.cancel()
            return true
        }
        guard installed else {
            if let stopgap {
                await stopgap.value
            } else {
                assembler.notice(LiveCaptionNotice.unavailable(languageName: plan.languageName))
            }
            return true
        }

        // Attaching finishes the stopgap's stream; the new stream queues audio until it is done.
        let (audio, offset) = router.attach()
        await stopgap?.value
        do {
            try await engine.run(audio: audio, startOffset: offset)
        } catch {
            guard !Task.isCancelled else { return true }
            assembler.notice(LiveCaptionNotice.unavailable(languageName: plan.languageName))
        }
        return true
    }
    #endif

    /// First candidate locale whose recognizer can run fully on-device. Never returns a
    /// recognizer that would use Apple's servers.
    static func makeOnDeviceRecognizer(candidates: [String]) -> SFSpeechRecognizer? {
        for identifier in candidates {
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)),
                  recognizer.isAvailable,
                  recognizer.supportsOnDeviceRecognition else { continue }
            // Keep result callbacks off the main thread so captions never block the UI.
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            queue.qualityOfService = .userInitiated
            recognizer.queue = queue
            return recognizer
        }
        return nil
    }
}
