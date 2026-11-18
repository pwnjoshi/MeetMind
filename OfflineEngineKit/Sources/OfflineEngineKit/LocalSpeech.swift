import Foundation
import WhisperKit
import FluidAudio
import CoreML

/// Overrides the SDK's tokenizer downloader: a corrupt/missing tokenizer fails
/// locally rather than falling through to a network request during inference.
private final class LocalOnlyWhisper: WhisperKit {
    override func loadTokenizerIfNeeded() async throws {
        guard tokenizer == nil else { return }
        guard let modelFolder else { throw OfflineError.unavailable("Missing local tokenizer folder.") }
        tokenizer = try await LocalWhisperTokenizer(folder: modelFolder)
    }
}

private struct LocalWhisperTokenizer: WhisperTokenizer {
    let base: TokenizerWrapper
    let specialTokens: SpecialTokens
    let allLanguageTokens: Set<Int>

    init(folder: URL) async throws {
        let base = try await AutoTokenizerWrapper.from(modelFolder: folder)
        func token(_ name: String) throws -> Int {
            guard let value = base.convertTokenToId(name) else {
                throw OfflineError.unavailable("Local tokenizer is missing a required speech token.")
            }
            return value
        }
        specialTokens = try SpecialTokens(
            endToken: token("<|endoftext|>"), englishToken: token("<|en|>"),
            noSpeechToken: token("<|nospeech|>"), noTimestampsToken: token("<|notimestamps|>"),
            specialTokenBegin: token("<|endoftext|>"), startOfPreviousToken: token("<|startofprev|>"),
            startOfTranscriptToken: token("<|startoftranscript|>"), timeTokenBegin: token("<|0.00|>"),
            transcribeToken: token("<|transcribe|>"), translateToken: token("<|translate|>"), whitespaceToken: 220)
        allLanguageTokens = Set(Constants.languages.values.compactMap { base.convertTokenToId("<|\($0)|>") })
        self.base = base
    }
    func encode(text: String) -> [Int] { base.encode(text: text) }
    func decode(tokens: [Int]) -> String { base.decode(tokens: tokens) }
    func convertTokenToId(_ token: String) -> Int? { base.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { base.convertIdToToken(id) }

    // Hindi and English both use whitespace. Accumulate byte-level tokens until
    // their Unicode is complete before forming words; retain punctuation tokens.
    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        var words: [String] = [], groups: [[Int]] = [], pending: [Int] = []
        for token in tokenIds {
            pending.append(token)
            let piece = decode(tokens: pending)
            if piece.contains("\u{fffd}") { continue }
            if words.isEmpty || piece.hasPrefix(" ") || token >= specialTokens.specialTokenBegin {
                words.append(piece); groups.append(pending)
            } else {
                words[words.count - 1] += piece
                groups[groups.count - 1] += pending
            }
            pending = []
        }
        if !pending.isEmpty { words.append(decode(tokens: pending)); groups.append(pending) }
        return (words, groups)
    }
}

public struct SpeakerSpan: Codable, Sendable {
    public let speaker: String
    public let start: Double
    public let end: Double
}

enum LocalSpeech {
    static func transcribe(audio: URL, folder: URL) async throws -> [AnalysisTurn] {
        let engine = try await LocalOnlyWhisper(WhisperKitConfig(modelFolder: folder.path,
            verbose: false, logLevel: .none, prewarm: true, load: true, download: false))
        do {
            let results = try await engine.transcribe(audioPath: audio.path,
                audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental(chunkDurationSeconds: 30, maxBufferedChunks: 1)),
                decodeOptions: DecodingOptions(task: .transcribe, language: nil, usePrefillPrompt: false,
                    detectLanguage: true, skipSpecialTokens: true, wordTimestamps: true, concurrentWorkerCount: 1),
                callback: { _ in !Task.isCancelled })
            var turns: [AnalysisTurn] = []
            for segment in results.flatMap(\.segments) {
                turns.append(AnalysisTurn(id: "t\(turns.count + 1)", text: segment.text,
                    start: Double(segment.start), end: Double(segment.end), speaker: nil))
            }
            await engine.unloadModels()
            try Task.checkCancellation()
            return turns
        } catch {
            await engine.unloadModels()
            throw error
        }
    }

    static func diarize(audio: URL, folder: URL) async throws -> [SpeakerSpan] {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        func load(_ name: String) throws -> MLModel {
            try MLModel(contentsOf: folder.appendingPathComponent(name + ".mlmodelc"), configuration: configuration)
        }
        let data = try Data(contentsOf: folder.appendingPathComponent("plda-parameters.json"))
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tensors = root["tensors"] as? [String: Any], let psi = tensors["psi"] as? [String: Any],
              let encoded = psi["data_base64"] as? String, let bytes = Data(base64Encoded: encoded), bytes.count % 4 == 0 else {
            throw OfflineError.unavailable("Invalid local speaker model parameters.")
        }
        var floats = [Float](repeating: 0, count: bytes.count / 4)
        _ = floats.withUnsafeMutableBytes { bytes.copyBytes(to: $0) }
        let models = try OfflineDiarizerModels(segmentationModel: load("Segmentation"),
            fbankModel: load("FBank"), embeddingModel: load("Embedding"), pldaRhoModel: load("PldaRho"),
            pldaPsi: floats.map(Double.init), compilationDuration: 0)
        var config = OfflineDiarizerConfig()
        config.segmentation.batchSize = 4
        config.embedding.batchSize = 4
        let manager = OfflineDiarizerManager(config: config)
        manager.initialize(models: models)
        let result = try await manager.process(audio)
        try Task.checkCancellation()
        return result.segments.map { SpeakerSpan(speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds)) }
    }
}
