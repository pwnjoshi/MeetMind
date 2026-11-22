import SwiftUI
import AVFoundation

/// Drives a short local microphone check. The clip is written to a temporary file and
/// deleted when the test ends or the screen closes.
@MainActor
@Observable
final class MicrophoneTestModel: NSObject, AVAudioPlayerDelegate {
    enum Phase: Equatable {
        case idle
        case recording
        case recorded
        case playing
        case denied
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var levels: [CGFloat] = Array(repeating: 0.05, count: 12)
    private(set) var heardInput = false

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var meterTask: Task<Void, Never>?
    private let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("manent-mic-test.m4a")

    func start() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            beginRecording()
        case .denied:
            phase = .denied
        default:
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in
                    if granted { self.beginRecording() } else { self.phase = .denied }
                }
            }
        }
    }

    private func beginRecording() {
        stopPlayback()
        cleanUpFile()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1
            ]
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                phase = .failed("The microphone could not start.")
                return
            }
            self.recorder = recorder
            heardInput = false
            phase = .recording
            startMetering()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let recorder = self.recorder, recorder.isRecording else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                let level = CGFloat(max(0.05, min(1, (power + 50) / 50)))
                if level > 0.2 { self.heardInput = true }
                self.levels.removeFirst()
                self.levels.append(level)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stopRecording() {
        meterTask?.cancel()
        recorder?.stop()
        recorder = nil
        phase = FileManager.default.fileExists(atPath: fileURL.path) ? .recorded : .idle
    }

    func play() {
        do {
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.delegate = self
            guard player.play() else {
                phase = .failed("Playback could not start.")
                return
            }
            self.player = player
            phase = .playing
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        if phase == .playing { phase = .recorded }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            if self.phase == .playing { self.phase = .recorded }
        }
    }

    /// Stops everything and deletes the temporary clip.
    func finish() {
        meterTask?.cancel()
        recorder?.stop()
        recorder = nil
        player?.stop()
        player = nil
        cleanUpFile()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        phase = .idle
    }

    private func cleanUpFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// H6 Test microphone (Settings only).
@MainActor
struct TestMicrophoneView: View {
    @State private var model = MicrophoneTestModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.manentAccent)
                .frame(width: 88, height: 88)
                .background(Theme.Colors.manentAccent.opacity(0.22), in: Circle())
                .padding(.top, 24)
                .accessibilityHidden(true)
            Text("Read this aloud").font(.title3.bold())
            Text("\u{201C}Let\u{2019}s review the budget and agree on next steps.\u{201D}")
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            meterCard
            controls
            statusLine
            Spacer()
        }
        .padding(.horizontal, 16)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Test Microphone")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.finish() }
    }

    private var meterCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill").foregroundStyle(model.heardInput ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.heardInput ? "Input detected" : "Waiting for input").font(.subheadline.weight(.semibold))
                Text("iPhone microphone").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 3) {
                ForEach(model.levels.indices, id: \.self) { index in
                    Capsule()
                        .fill(Color.green.opacity(0.7))
                        .frame(width: 4, height: 6 + model.levels[index] * 24)
                }
            }
            .frame(height: 30)
            .accessibilityHidden(true)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var controls: some View {
        switch model.phase {
        case .recording:
            Button { model.stopRecording() } label: {
                Label("Stop", systemImage: "stop.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.coralRed)
            .buttonBorderShape(.capsule)
        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Text("Open Settings").font(.headline).frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.manentAccent)
            .buttonBorderShape(.capsule)
        case .recorded, .playing:
            HStack(spacing: 12) {
                Button { model.start() } label: {
                    Text("Record Again").font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                Button {
                    if model.phase == .playing { model.stopPlayback() } else { model.play() }
                } label: {
                    Text(model.phase == .playing ? "Stop" : "Play Back")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.manentAccent)
                .buttonBorderShape(.capsule)
            }
        default:
            Button { model.start() } label: {
                Text("Start Test").font(.headline).frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.manentAccent)
            .buttonBorderShape(.capsule)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch model.phase {
        case .denied:
            Text("Microphone access is off for Manent. Turn it on in Settings.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        case .failed(let message):
            Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
        default:
            Text("Deleted after the test.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
