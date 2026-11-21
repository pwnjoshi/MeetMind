import AVFoundation
import Observation

/// Plays one short clip of the meeting audio at a time. Starting a clip stops the previous one,
/// and each clip stops by itself at the end of its segment.
@Observable
@MainActor
final class VoiceSamplePlayer {
    private(set) var playingSampleID: UUID?
    var errorMessage: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private var stopTask: Task<Void, Never>?

    func isPlaying(_ sample: MeetingVoiceSample) -> Bool {
        playingSampleID == sample.id
    }

    /// Plays the clip, or stops it when it is already playing.
    func toggle(_ sample: MeetingVoiceSample, audioURL: URL) {
        if playingSampleID == sample.id {
            stop()
            return
        }
        stop()
        do {
            let audio = try preparedPlayer(for: audioURL)
            let start = max(0, min(sample.startTime, max(0, audio.duration - 0.05)))
            audio.currentTime = start
            guard audio.play() else {
                errorMessage = "This clip could not be played."
                return
            }
            playingSampleID = sample.id
            watchEnd(of: sample)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        playingSampleID = nil
    }

    private func preparedPlayer(for url: URL) throws -> AVAudioPlayer {
        if let player, loadedURL == url { return player }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let audio = try AVAudioPlayer(contentsOf: url)
        audio.prepareToPlay()
        player = audio
        loadedURL = url
        return audio
    }

    private func watchEnd(of sample: MeetingVoiceSample) {
        let sampleID = sample.id
        let end = sample.endTime
        stopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let audio = self.player else { return }
                if !audio.isPlaying || audio.currentTime >= end { break }
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
            guard !Task.isCancelled, let self, self.playingSampleID == sampleID else { return }
            self.stop()
        }
    }
}