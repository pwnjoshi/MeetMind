import SwiftUI
import SwiftData
import Observation

/// Playback state for one saved recording, backed by the app's AudioPlaybackService.
@Observable
@MainActor
final class RecordingPlayerModel {
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var isLoaded = false
    var rate: Float = 1.0 {
        didSet { service.playbackRate = rate }
    }
    var errorMessage: String?

    private let service = AudioPlaybackService()

    func load(url: URL) {
        guard !isLoaded else { return }
        do {
            try service.loadAudio(url: url)
            duration = service.duration
            isLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePlayback() {
        guard isLoaded else { return }
        if service.isPlaying {
            service.pause()
        } else {
            if duration > 0, service.currentTime >= duration - 0.1 { service.seek(to: 0) }
            do { try service.play() } catch { errorMessage = error.localizedDescription }
        }
        sync()
    }

    func skip(by seconds: TimeInterval) {
        guard isLoaded else { return }
        seek(to: service.currentTime + seconds)
    }

    func seek(to time: TimeInterval) {
        guard isLoaded else { return }
        service.seek(to: max(0, min(time, duration)))
        sync()
    }

    func sync() {
        currentTime = service.currentTime
        isPlaying = service.isPlaying
        if isPlaying == false, service.state == .completed { currentTime = duration }
    }

    func stop() {
        service.stop()
        isPlaying = false
    }
}

/// Recording · Audio player (Figma 735:1501).
struct RecordingPlayerView: View {
    let meeting: Meeting
    @Environment(NavigationRouter.self) private var router: NavigationRouter?
    @Environment(AppState.self) private var appState: AppState?
    @State private var model = RecordingPlayerModel()
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0

    private static let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        let shownTime = isScrubbing ? scrubTime : model.currentTime
        let length = max(model.duration, 1)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Saved on this iPhone").font(.subheadline).foregroundStyle(.secondary)
                    ProgressBars(progress: shownTime / length)
                        .frame(height: 48)
                        .accessibilityHidden(true)
                    Slider(
                        value: Binding(get: { shownTime }, set: { scrubTime = $0 }),
                        in: 0...length,
                        onEditingChanged: { editing in
                            if editing {
                                scrubTime = model.currentTime
                                isScrubbing = true
                            } else {
                                model.seek(to: scrubTime)
                                isScrubbing = false
                            }
                        }
                    )
                    .disabled(!model.isLoaded)
                    .accessibilityLabel("Playback position")
                    HStack {
                        Text(LocalRecordingStorage.formatted(duration: shownTime))
                        Spacer()
                        Text(LocalRecordingStorage.formatted(duration: model.duration))
                    }
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    HStack(spacing: 12) {
                        Button { model.skip(by: -15) } label: {
                            Image(systemName: "gobackward.15").frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered).accessibilityLabel("Back 15 seconds")
                        Button { model.togglePlayback() } label: {
                            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                        Button { model.skip(by: 15) } label: {
                            Image(systemName: "goforward.15").frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered).accessibilityLabel("Forward 15 seconds")
                    }
                    .disabled(!model.isLoaded)
                    HStack {
                        Text("Speed").foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            Picker("Speed", selection: Binding(get: { model.rate }, set: { model.rate = $0 })) {
                                ForEach(Self.rates, id: \.self) { value in
                                    Text(Self.rateTitle(value)).tag(value)
                                }
                            }
                        } label: {
                            Text(Self.rateTitle(model.rate))
                        }
                    }
                    .font(.subheadline)
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))

                VStack(spacing: 0) {
                    LabeledContent("Size", value: LocalRecordingStorage.formatted(bytes: fileBytes))
                        .padding(.vertical, 12)
                    Divider()
                    LabeledContent("Availability", value: "On This iPhone")
                        .padding(.vertical, 12)
                }
                .padding(.horizontal, 16)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))

                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }

                Button {
                    model.stop()
                    appState?.activeTab = .home
                    router?.navigate(to: .meetingDetail(id: meeting.id), in: .home)
                } label: {
                    Text("Open Meeting").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(router == nil)
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(meeting.title)
        .navigationBarTitleDisplayMode(.large)
        .tint(Theme.Colors.manentAccent)
        .task {
            if let url = meeting.resolvedAudioFileURL {
                model.load(url: url)
            } else {
                model.errorMessage = "The audio file for this meeting is no longer on this iPhone."
            }
            while !Task.isCancelled {
                model.sync()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        .onDisappear { model.stop() }
    }

    private var fileBytes: Int64 {
        guard let url = meeting.resolvedAudioFileURL else { return 0 }
        return LocalRecordingStorage.fileSize(at: url)
    }

    private static func rateTitle(_ value: Float) -> String {
        value == value.rounded() ? "\(Int(value))×" : String(format: "%g×", Double(value))
    }
}

/// Decorative progress bars. They show playback position only, not audio levels.
private struct ProgressBars: View {
    let progress: Double
    private let count = 48

    var body: some View {
        GeometryReader { proxy in
            let barWidth = max(2, proxy.size.width / CGFloat(count) - 3)
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<count, id: \.self) { index in
                    let heights: [CGFloat] = [0.35, 0.7, 0.5, 1.0, 0.6, 0.85, 0.4, 0.75]
                    Capsule()
                        .fill(Double(index) / Double(count) <= progress ? Theme.Colors.manentAccent : Color.secondary.opacity(0.3))
                        .frame(width: barWidth, height: proxy.size.height * heights[index % heights.count])
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}
