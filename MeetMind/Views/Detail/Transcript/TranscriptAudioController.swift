import AVFoundation
import Foundation

/// Plays a meeting recording for the Transcript page. It only starts audio after an explicit tap,
/// refuses to play while a recording is running, and puts the audio session back when the page closes.
@MainActor
final class TranscriptAudioController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isLoaded = false
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var rate: Float = 1
    @Published private(set) var message: String?

    /// Returns true while the app is recording. Playback is refused then.
    var isRecordingActive: () -> Bool = { false }
    /// Called whenever the playhead moves.
    var onTimeChange: ((TimeInterval) -> Void)?

    private var player: AVAudioPlayer?
    private var loadedURL: URL?
    private var timer: Timer?
    private var savedCategory: AVAudioSession.Category?
    private var savedMode: AVAudioSession.Mode?
    private var savedOptions: AVAudioSession.CategoryOptions?

    // MARK: Loading

    func load(url: URL?) {
        guard let url, url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            unload()
            return
        }
        if loadedURL == url, player != nil {
            startTimer()
            return
        }
        unload()
        do {
            let created = try AVAudioPlayer(contentsOf: url)
            created.delegate = self
            created.enableRate = true
            created.rate = rate
            created.prepareToPlay()
            player = created
            loadedURL = url
            duration = created.duration
            currentTime = 0
            isLoaded = created.duration > 0
            startTimer()
        } catch {
            isLoaded = false
            player = nil
            loadedURL = nil
        }
    }

    /// Stops playback, releases the file and restores the audio session.
    func unload() {
        stopTimer()
        player?.stop()
        player = nil
        loadedURL = nil
        isPlaying = false
        isLoaded = false
        currentTime = 0
        duration = 0
        restoreSession()
    }

    // MARK: Transport

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard let player else { return }
        if isRecordingActive() {
            message = "Stop the recording before playing audio."
            return
        }
        activateSession()
        player.enableRate = true
        player.rate = rate
        if player.currentTime >= player.duration - 0.05 { player.currentTime = 0 }
        if player.play() {
            message = nil
            isPlaying = true
        } else {
            message = "This recording could not be played."
            isPlaying = false
        }
        sync()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        sync()
    }

    func play(from time: TimeInterval) {
        guard player != nil else { return }
        seek(to: time)
        play()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let target = min(max(0, time), max(0, player.duration - 0.05))
        player.currentTime = target
        currentTime = target
        onTimeChange?(target)
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func cycleRate() {
        rate = StickyAudioPlayerBar.nextRate(after: rate)
        player?.enableRate = true
        player?.rate = rate
    }

    // MARK: Timer

    private func startTimer() {
        guard timer == nil else { return }
        let created = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
        RunLoop.main.add(created, forMode: .common)
        timer = created
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Copies the player's real state, which also catches system interruptions.
    private func sync() {
        guard let player else { return }
        if isPlaying != player.isPlaying { isPlaying = player.isPlaying }
        let time = player.currentTime
        if abs(time - currentTime) > 0.02 {
            currentTime = time
            onTimeChange?(time)
        }
    }

    // MARK: Audio session

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        if savedCategory == nil {
            savedCategory = session.category
            savedMode = session.mode
            savedOptions = session.categoryOptions
        }
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    private func restoreSession() {
        guard let category = savedCategory else { return }
        let mode = savedMode ?? .default
        let options = savedOptions ?? []
        savedCategory = nil
        savedMode = nil
        savedOptions = nil
        // A recording that started meanwhile owns the session.
        guard !isRecordingActive() else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(category, mode: mode, options: options)
    }

    // MARK: AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.finished()
        }
    }

    private func finished() {
        isPlaying = false
        player?.currentTime = 0
        currentTime = 0
        onTimeChange?(0)
    }
}
