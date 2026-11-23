import SwiftUI
import SwiftData
import AVFoundation
import Speech
import Observation
import UIKit
import OfflineEngineKit

/// Listens on this iPhone for the phrase "Hey Vidur" while the app is open. Opt-in, off by default.
///
/// Privacy and power:
/// - Runs only while the app is in the foreground, no meeting is being recorded, the Vidur sheet is closed
///   and no other app is playing audio. Any of those changing stops it at once.
/// - Uses on-device speech recognition only. Nothing is stored or sent. Only the words said after the
///   phrase are passed on, and only when the phrase is heard.
/// - Each recognition cycle is short and restarts itself, with a growing pause after errors.
@MainActor
@Observable
final class VidurWakeWordListener {
    static let shared = VidurWakeWordListener()

    private(set) var isListening = false
    /// Called with what was said after "Hey Vidur" (possibly empty).
    @ObservationIgnored var onWake: (@MainActor (String) -> Void)?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var cycleTask: Task<Void, Never>?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var latestRemainder = ""
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private static let cycleSeconds: TimeInterval = 55
    private static let settleSeconds: TimeInterval = 1.3

    /// Call whenever the setting, the scene phase, recording or the Vidur sheet changes.
    func update(enabled: Bool, isActive: Bool, isRecording: Bool, vidurOpen: Bool) {
        installObserversIfNeeded()
        wanted = enabled && isActive && !isRecording && !vidurOpen && VidurPermissions.isAuthorized
        if wanted {
            beginCycle()
        } else {
            stop()
        }
    }

    func stop() {
        wanted = false
        retryTask?.cancel()
        retryTask = nil
        wakeTask?.cancel()
        wakeTask = nil
        tearDown()
    }

    // MARK: Cycle

    private func beginCycle() {
        guard wanted, !isListening else { return }
        let session = AVAudioSession.sharedInstance()
        // Another app or a Vidur voice reply is using audio, so stay out of its way and look again later.
        if session.isOtherAudioPlaying || VidurSpeaker.shared.isSpeaking {
            scheduleRetry(after: 15)
            return
        }
        guard let recognizer = VidurPermissions.onDeviceRecognizer(
            locales: [Locale(identifier: "en-IN"), Locale(identifier: "en-US")]) else {
            wanted = false
            return
        }
        do {
            try VidurAudioSession.activateForListening()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw VidurVoiceError.noMicrophone }
            VidurMicTap.install(on: input, format: format, request: request)
            engine.prepare()
            try engine.start()
            generation += 1
            let current = generation
            self.request = request
            latestRemainder = ""
            task = VidurMicTap.startTask(recognizer: recognizer, request: request) { [weak self] text, _, failed in
                Task { @MainActor in
                    self?.handle(text: text, failed: failed, generation: current)
                }
            }
            isListening = true
            cycleTask?.cancel()
            cycleTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.cycleSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.cycleEnded(generation: current)
            }
        } catch {
            tearDown()
            registerFailure()
        }
    }

    private func handle(text: String?, failed: Bool, generation gen: Int) {
        guard gen == generation, isListening else { return }
        if let text, let match = VidurWakeWord.detect(in: text) {
            latestRemainder = match.remainder
            // Wait for the user to finish the sentence ("Hey Vidur, what is overdue?") before handing over.
            wakeTask?.cancel()
            wakeTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.settleSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.fireWake(generation: gen)
            }
            return
        }
        if failed { restartAfterFailure(generation: gen) }
    }

    private func fireWake(generation gen: Int) {
        guard gen == generation, isListening, wanted else { return }
        let spoken = latestRemainder
        tearDown()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onWake?(spoken)
    }

    private func cycleEnded(generation gen: Int) {
        guard gen == generation, isListening else { return }
        tearDown()
        failures = 0
        scheduleRetry(after: 0.4)
    }

    private func restartAfterFailure(generation gen: Int) {
        guard gen == generation else { return }
        tearDown()
        registerFailure()
    }

    private func registerFailure() {
        failures += 1
        scheduleRetry(after: min(30, TimeInterval(1 << min(failures, 5))))
    }

    private func scheduleRetry(after seconds: TimeInterval) {
        retryTask?.cancel()
        guard wanted else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.beginCycle()
        }
    }

    private func tearDown() {
        cycleTask?.cancel()
        cycleTask = nil
        generation += 1
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        if isListening {
            isListening = false
            VidurAudioSession.deactivate()
        }
    }

    // MARK: System events

    private func installObserversIfNeeded() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification,
            AVAudioSession.interruptionNotification,
            AVAudioSession.silenceSecondaryAudioHintNotification
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.systemEvent() }
            }
            observers.append(token)
        }
    }

    /// Another app wants audio, the app is leaving the foreground or a call came in: stop now,
    /// and let the next `update` or the retry timer bring the listener back when it is safe.
    private func systemEvent() {
        guard isListening else { return }
        tearDown()
        scheduleRetry(after: 10)
    }
}

// MARK: - Indicator

/// A small pill in the system's style that shows while Vidur is waiting for "Hey Vidur".
struct VidurListeningIndicator: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.orange).frame(width: 6, height: 6)
            Text("Listening for \u{201C}Hey Vidur\u{201D}")
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 2)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vidur is listening for Hey Vidur on this iPhone")
    }
}

// MARK: - App-level hook

/// Starts and stops the "Hey Vidur" listener from the app's lifecycle and opens Vidur when it hears the phrase.
struct VidurWakeWordModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @AppStorage(VidurVoiceSettings.heyVidurKey) private var enabled = false
    @State private var showsVidur = false
    @State private var vidurMeetingID: UUID?

    @MainActor private var listener: VidurWakeWordListener { VidurWakeWordListener.shared }
    @MainActor private var coordinator: VidurVoiceCoordinator { VidurVoiceCoordinator.shared }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if listener.isListening { VidurListeningIndicator() }
            }
            .sheet(isPresented: $showsVidur) {
                if let id = vidurMeetingID {
                    NavigationStack {
                        RootAskAISheet(meetingId: id, modelContext: modelContext) { showsVidur = false }
                    }
                }
            }
            .onAppear {
                listener.onWake = { text in openVidur(with: text) }
                refresh()
            }
            .onChange(of: scenePhase) { _, _ in refresh() }
            .onChange(of: appState.isRecordingActive) { _, _ in refresh() }
            .onChange(of: enabled) { _, _ in refresh() }
            .onChange(of: coordinator.isSheetOpen) { _, _ in refresh() }
            .onChange(of: showsVidur) { _, _ in refresh() }
    }

    @MainActor private func refresh() {
        listener.update(enabled: enabled, isActive: scenePhase == .active, isRecording: appState.isRecordingActive,
                        vidurOpen: coordinator.isSheetOpen || showsVidur)
    }

    @MainActor private func openVidur(with text: String) {
        guard !appState.isRecordingActive, !showsVidur, appState.activeSheet == nil else { return }
        let meetings = (try? modelContext.fetch(FetchDescriptor<Meeting>())) ?? []
        func start(_ meeting: Meeting) -> Date { meeting.scheduledStartTime ?? meeting.createdAt }
        let now = Date()
        let upcoming = meetings.filter { $0.status == .scheduled && start($0) >= now }.min { start($0) < start($1) }
        guard let target = upcoming ?? meetings.max(by: { start($0) < start($1) }) else { return }
        coordinator.pendingWake = VidurWakeRequest(text: text)
        vidurMeetingID = target.id
        showsVidur = true
    }
}

extension View {
    /// Adds the opt-in "Hey Vidur" listener. Does nothing unless the user turned it on in Vidur settings.
    func vidurWakeWord() -> some View { modifier(VidurWakeWordModifier()) }
}
