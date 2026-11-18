import Foundation
import Darwin
import AVFoundation

public struct BenchmarkResult: Codable, Sendable {
    public let engine: String
    public let modelRevision: String
    public let elapsedSeconds: Double
    public let sampledPeakFootprintBytes: UInt64
    public let thermalState: Int
    public let turns: [AnalysisTurn]
    public let speakers: [SpeakerSpan]
    public let analysis: [LocalAnalysisResult]
}

public actor OfflineBenchmarkRunner {
    public init() {}

    public static var syntheticAudioURL: URL? {
        Bundle.module.url(forResource: "synthetic-smoke", withExtension: "aiff")
    }

    public static let syntheticTurns = [
        AnalysisTurn(id: "t1", text: "Rahul, kal tak estimate bhej dena.", start: 0, end: 3, speaker: "Speaker 1"),
        AnalysisTurn(id: "t2", text: "Haan, main kal bhej dunga. Rahul bol raha hoon.", start: 3, end: 7, speaker: "Speaker 2"),
        AnalysisTurn(id: "t3", text: "Website redesign abhi mat karna. We have cancelled that task.", start: 7, end: 12, speaker: "Speaker 1"),
        AnalysisTurn(id: "t4", text: "Should we research another vendor? No, not this week. No decision on that yet.", start: 12, end: 17, speaker: "Speaker 1"),
    ]

    private nonisolated static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : 0
    }

    public func run(profile: ModelProfile, audio: URL? = nil, turns input: [AnalysisTurn] = []) async throws -> BenchmarkResult {
        try Task.checkCancellation()
        if let audio {
            let duration = try await AVURLAsset(url: audio).load(.duration).seconds
            guard duration.isFinite, duration > 0, duration <= 3600 else {
                throw OfflineError.unavailable("Benchmark recordings must be between 0 and 60 minutes long.")
            }
        }
        guard ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else {
            throw OfflineError.unavailable("iPhone is too warm to start a benchmark. Let it cool down and retry.")
        }
        let folder = try await OfflineModelStore.shared.verifiedFolder(profile)
        let start = Date()
        let sampler = Task.detached { () -> UInt64 in
            var peak: UInt64 = 0
            while !Task.isCancelled {
                peak = max(peak, Self.footprint())
                do { try await Task.sleep(nanoseconds: 200_000_000) } catch { break }
            }
            return peak
        }
        defer { sampler.cancel() }
        var turns: [AnalysisTurn] = [], speakers: [SpeakerSpan] = [], analysis: [LocalAnalysisResult] = []
        if profile.id.hasPrefix("whisper") {
            guard let audio else { throw OfflineError.unavailable("Choose a local recording first.") }
            turns = try await LocalSpeech.transcribe(audio: audio, folder: folder)
        } else if profile.id == "diarization" {
            guard let audio else { throw OfflineError.unavailable("Choose a local recording first.") }
            speakers = try await LocalSpeech.diarize(audio: audio, folder: folder)
        } else if profile.id.hasPrefix("qwen") {
            guard !input.isEmpty else { throw OfflineError.unavailable("Transcribe audio or use the synthetic text fixture first.") }
            let model = try LocalLanguageModel(url: folder.appendingPathComponent("model.gguf"))
            var chunks: [[AnalysisTurn]] = [], chunk: [AnalysisTurn] = [], characters = 0
            for turn in input {
                guard turn.text.count <= 4000 else { throw OfflineError.unavailable("One transcript turn is too long. Split it before analysis.") }
                if characters + turn.text.count > 4000 && !chunk.isEmpty {
                    chunks.append(chunk)
                    chunk = Array(chunk.suffix(2))
                    characters = chunk.reduce(0) { $0 + $1.text.count }
                }
                chunk.append(turn); characters += turn.text.count
            }
            if !chunk.isEmpty { chunks.append(chunk) }
            for chunk in chunks {
                try Task.checkCancellation()
                analysis.append(try model.analyze(turns: chunk, meetingDate: start, timezone: TimeZone.current.identifier))
            }
        } else {
            throw OfflineError.unavailable("Unknown benchmark engine.")
        }
        sampler.cancel()
        let peak = max(Self.footprint(), await sampler.value)
        return BenchmarkResult(engine: profile.id, modelRevision: profile.revision,
            elapsedSeconds: Date().timeIntervalSince(start), sampledPeakFootprintBytes: peak,
            thermalState: ProcessInfo.processInfo.thermalState.rawValue, turns: turns, speakers: speakers, analysis: analysis)
    }

    public static func save(_ result: BenchmarkResult) throws {
        let root = try OfflineModelStore.privateDirectory("Results")
        let name = "\(result.engine)-\(UUID().uuidString).json"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: root.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Exportable telemetry deliberately excludes audio, transcript, titles,
        // participants, quotes and analysis. No meeting text leaves the device.
        var metricsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BenchmarkMetrics", isDirectory: true)
        try FileManager.default.createDirectory(at: metricsRoot, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try metricsRoot.setResourceValues(values)
        let metrics: [String: Any] = ["engine": result.engine, "revision": result.modelRevision,
            "elapsedSeconds": result.elapsedSeconds, "sampledPeakFootprintBytes": result.sampledPeakFootprintBytes,
            "thermalState": result.thermalState, "qualified": false]
        try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
            .write(to: metricsRoot.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
