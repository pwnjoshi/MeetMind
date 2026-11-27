import Foundation

/// Counters for per-region speech decoding. They hold numbers only, never audio or text,
/// so they are safe to log.
public struct SpeechDecodeStats: Equatable, Sendable, CustomStringConvertible {
    /// Transcription runs (one per audio file or live window).
    public var runs = 0
    /// Runs that decoded the whole file in one language instead of splitting it into regions.
    public var wholeFileRuns = 0
    /// Speech regions decoded.
    public var regions = 0
    /// Regions whose language was detected automatically (one encoder pass each).
    public var detections = 0
    /// Regions decoded a second time because the detected language was corrected.
    public var redecodes = 0
    public var audioSeconds = 0.0
    public var speechSeconds = 0.0
    /// Time spent planning regions and decoding them.
    public var planSeconds = 0.0
    public var decodeSeconds = 0.0

    public init() {}

    public mutating func add(_ other: SpeechDecodeStats) {
        runs += other.runs
        wholeFileRuns += other.wholeFileRuns
        regions += other.regions
        detections += other.detections
        redecodes += other.redecodes
        audioSeconds += other.audioSeconds
        speechSeconds += other.speechSeconds
        planSeconds += other.planSeconds
        decodeSeconds += other.decodeSeconds
    }

    public var description: String {
        func rounded(_ value: Double) -> String { String(format: "%.1f", value) }
        return "speech runs=\(runs) wholeFile=\(wholeFileRuns) regions=\(regions) detections=\(detections) "
            + "redecodes=\(redecodes) audio=\(rounded(audioSeconds))s speech=\(rounded(speechSeconds))s "
            + "plan=\(rounded(planSeconds))s decode=\(rounded(decodeSeconds))s"
    }
}

/// Process-wide totals of `SpeechDecodeStats`, plus the most recent run.
public enum SpeechDiagnostics {
    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var total = SpeechDecodeStats()
        private var latest = SpeechDecodeStats()

        func record(_ run: SpeechDecodeStats) {
            lock.lock()
            total.add(run)
            latest = run
            lock.unlock()
        }

        func read() -> (total: SpeechDecodeStats, latest: SpeechDecodeStats) {
            lock.lock()
            defer { lock.unlock() }
            return (total, latest)
        }

        func clear() {
            lock.lock()
            total = SpeechDecodeStats()
            latest = SpeechDecodeStats()
            lock.unlock()
        }
    }

    private static let store = Store()

    /// Totals since launch or the last `reset()`.
    public static func totals() -> SpeechDecodeStats { store.read().total }

    /// The most recent transcription run.
    public static func lastRun() -> SpeechDecodeStats { store.read().latest }

    public static func reset() { store.clear() }

    static func record(_ run: SpeechDecodeStats) { store.record(run) }
}
