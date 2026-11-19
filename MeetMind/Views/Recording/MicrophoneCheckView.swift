import SwiftUI
import AVFoundation

/// Microphone check screen matching Figma node 161:1089
public struct MicrophoneCheckView: View {
    @Environment(\.dismiss) private var dismiss
    public let onStartRecording: () -> Void
    @State private var recorder = AudioRecordingService()
    @State private var levels: [Float] = Array(repeating: 0, count: 32)
    @State private var inputDetected = false
    @State private var microphoneReady = false
    @State private var microphoneError: String?
    @State private var playback = AudioPlaybackService()
    @State private var sampleReady = false
    @State private var stoppingSample = false
    @State private var testRun = UUID()
    @State private var capturingSample = false
    @State private var sampleDuration: TimeInterval = 0
    @State private var showsTroubleshooting = false
    
    public init(onStartRecording: @escaping () -> Void, visualSampleDuration: TimeInterval? = nil) {
        self.onStartRecording = onStartRecording
        if let visualSampleDuration {
            self._sampleReady = State(initialValue: true)
            self._sampleDuration = State(initialValue: visualSampleDuration)
            self._inputDetected = State(initialValue: true)
            self._levels = State(initialValue: [0.18, 0.42, 0.24, 0.54, 0.31, 0.66, 0.38, 0.51,
                                                0.28, 0.73, 0.34, 0.61, 0.44, 0.69, 0.32, 0.57,
                                                0.41, 0.77, 0.36, 0.62, 0.29, 0.70, 0.45, 0.58,
                                                0.33, 0.67, 0.39, 0.74, 0.30, 0.55, 0.43, 0.64])
        }
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: "#F0F3FA"))
                    .clipShape(Circle())
            }
            .padding(.top, 8)
            .accessibilityLabel("Close microphone test")
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Test Microphone")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                Text("Read this aloud, then play it back.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            
            MicWaveformCardView(
                levels: levels,
                durationText: sampleReady
                    ? Duration.seconds(sampleDuration).formatted(.time(pattern: .minuteSecond))
                    : nil
            )
            
            HStack(spacing: 12) {
                Circle()
                    .fill(inputDetected ? Color(hex: "#10B981") : .gray)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(microphoneError != nil ? "Microphone test unavailable" : (inputDetected ? "Input Detected" : "Ready to record a sample"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(microphoneError ?? AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "iPhone Microphone")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                Spacer()
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24))

            if microphoneError != nil && !sampleReady {
                Button("Troubleshoot Input") { showsTroubleshooting = true }
                    .frame(minHeight: 44)
            }
            
            if sampleReady {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Sample").font(.body)
                    Text("Does it sound clear?").font(.subheadline).foregroundStyle(.secondary)
                    Button("Play Sample", systemImage: "play.fill") {
                        do { playback.seek(to: 0); try playback.play() }
                        catch { microphoneError = error.localizedDescription }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            }

            Spacer(minLength: 24)

            if !sampleReady {
                Text("Deleted after the test.").font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Button {
                    if !capturingSample {
                        playback.stop()
                        try? recorder.cancelRecording()
                        recorder = AudioRecordingService()
                        inputDetected = false
                        levels = Array(repeating: 0, count: 32)
                        microphoneReady = false
                        microphoneError = nil
                        capturingSample = true
                        testRun = UUID()
                        return
                    }
                    stoppingSample = true
                    Task {
                        defer { stoppingSample = false }
                        do {
                            sampleDuration = recorder.currentDuration
                            let url = try await recorder.stopRecording()
                            capturingSample = false
                            try playback.loadAudio(url: url)
                            sampleReady = true
                        } catch {
                            microphoneError = error.localizedDescription
                            capturingSample = false
                            microphoneReady = false
                            try? recorder.cancelRecording()
                        }
                    }
                }
                label: {
                    Text(capturingSample ? "Stop Sample" : "Record Sample")
                        .frame(maxWidth: .infinity)
                }
                .disabled(stoppingSample || (capturingSample && !microphoneReady))
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .frame(maxWidth: .infinity)
            }
            
            Button(action: {
                playback.stop()
                try? recorder.cancelRecording()
                dismiss()
                onStartRecording()
            }) {
                Text(sampleReady ? "Sounds Good, Start Recording" : "Skip Test")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(sampleReady ? Color.white : Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(sampleReady ? Color(hex: "#0068D9") : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 26))
            }
            .padding(.bottom, 16)
            .disabled(stoppingSample || (capturingSample && !microphoneReady))
            if sampleReady {
                HStack {
                    Button("Record Again") {
                        playback.stop()
                        try? recorder.cancelRecording()
                        recorder = AudioRecordingService()
                        sampleReady = false
                        microphoneReady = false
                        capturingSample = true
                        inputDetected = false
                        microphoneError = nil
                        levels = Array(repeating: 0, count: 32)
                        testRun = UUID()
                    }
                    Spacer()
                    Button("Troubleshoot Input") { showsTroubleshooting = true }
                }
                .frame(minHeight: 44)
            }
        }
                .padding(.horizontal, 20)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .alert("Troubleshoot Input", isPresented: $showsTroubleshooting) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Check that microphone access is enabled for Manent in Settings. Move closer to the iPhone, keep its microphones uncovered, and disconnect an unwanted Bluetooth audio input. Then record another sample.")
        }
        .task(id: testRun) {
            guard capturingSample else { return }
            do {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("mic-check-\(UUID().uuidString).m4a")
                try await recorder.startRecording(destinationURL: url)
                guard !Task.isCancelled else { try recorder.cancelRecording(); return }
                microphoneReady = true
                for await level in recorder.audioMeterStream {
                    guard !Task.isCancelled else { break }
                    levels.removeLast()
                    levels.insert(level, at: 0)
                    inputDetected = inputDetected || level > 0.1
                }
            } catch {
                microphoneError = error.localizedDescription
                capturingSample = false
                microphoneReady = false
                try? recorder.cancelRecording()
            }
        }
        .onDisappear { playback.stop(); try? recorder.cancelRecording() }
    }
}
