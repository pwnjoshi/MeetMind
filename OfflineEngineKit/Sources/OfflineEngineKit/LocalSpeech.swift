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
        // Whisper's English-only vocabulary has 51,864 logits; multilingual
        // small has 51,865 and large-v3 has 51,866. SDK helper is internal.
        guard let logits = textDecoder.logitsSize, logits >= 51865 else {
            throw OfflineError.unavailable("A multilingual speech model is required for Hindi–English meetings.")
        }
        textDecoder.isModelMultilingual = true
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

/// Holds at most one loaded Whisper engine. 	ake hands it out exclusively, so two
/// concurrent transcriptions never share an engine; the second simply loads its own.
private final class SpeechEngineCache: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: LocalOnlyWhisper?
    private var folder: String?
    private var generation = 0
    private var prewarmed: Set<String> = []

    func take(folder: String) -> LocalOnlyWhisper? {
        lock.lock(); defer { lock.unlock() }
        guard self.folder == folder, let engine else { return nil }
        self.engine = nil
        self.folder = nil
        generation += 1
        return engine
    }

    /// Stores the engine and returns a generation token for idle eviction.
    func put(_ engine: LocalOnlyWhisper, folder: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        self.engine = engine
        self.folder = folder
        generation += 1
        return generation
    }

    func evict(ifGeneration expected: Int? = nil) -> LocalOnlyWhisper? {
        lock.lock(); defer { lock.unlock() }
        if let expected, expected != generation { return nil }
        let engine = self.engine
        self.engine = nil
        self.folder = nil
        generation += 1
        return engine
    }

    /// True only for the first load of older in this process.
    func claimPrewarm(folder: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return prewarmed.insert(folder).inserted
    }
}

enum LocalSpeech {
    /// Hindi-English conversations are commonly misidentified as Urdu by automatic
    /// detection. A nil language keeps automatic detection (Hinglish), but a result other
    /// than Hindi or English is decoded again as Hindi. The first Hindi detection is
    /// remembered in `memory` so later gaps and windows of the same meeting stay consistent.
    static func transcribe(audio: URL, folder: URL, languageCode: String? = nil,
                           vocabulary: SpeechVocabulary? = nil,
                           memory: SpeechLanguageMemory? = nil) async throws -> [AnalysisTurn] {
        let engine: LocalOnlyWhisper
        if let cached = engineCache.take(folder: folder.path) {
            engine = cached
        } else {
            if let stale = engineCache.evict() { await stale.unloadModels() }
            // Prewarming specializes each Core ML model with a lower memory peak but
            // doubles load time, so only the first load of a model per launch does it.
            engine = try await LocalOnlyWhisper(WhisperKitConfig(modelFolder: folder.path,
                computeOptions: speechComputeOptions,
                verbose: false, logLevel: .none, prewarm: engineCache.claimPrewarm(folder: folder.path),
                load: true, download: false))
        }
        do {
            _ = try? await engine.loadTokenizerIfNeeded()
            var language: String? = languageCode ?? memory?.code
            let prompt = promptTokens(engine: engine, vocabulary: vocabulary, languageCode: language)
            var pass = try await decode(engine: engine, audio: audio, language: language, prompt: prompt)
            if languageCode == nil, language == nil {
                let detected = (pass.language ?? "").lowercased()
                if !detected.isEmpty, detected != "hi", detected != "en" {
                    pass = try await decode(engine: engine, audio: audio, language: "hi", prompt: prompt)
                    language = "hi"
                } else if detected == "hi" {
                    language = "hi"
                }
                if language == "hi" { memory?.remember("hi") }
            }
            try Task.checkCancellation()
            // Live recording windows arrive every 30 seconds and the final pass follows
            // soon after Stop, so the loaded engine is kept briefly instead of reloaded.
            keep(engine, folder: folder.path)
            return pass.turns
        } catch {
            await engine.unloadModels()
            throw error
        }
    }

    /// Mel spectrogram on the CPU and encoder/decoder on the Neural Engine. WhisperKit's
    /// default mel stage uses the GPU, which iOS denies to a backgrounded iPhone app.
    private static var speechComputeOptions: ModelComputeOptions {
        ModelComputeOptions(melCompute: .cpuOnly, audioEncoderCompute: .cpuAndNeuralEngine,
                            textDecoderCompute: .cpuAndNeuralEngine)
    }

    private static let engineCache = SpeechEngineCache()
    /// An idle cached engine is unloaded after this long.
    static let engineIdleSeconds: UInt64 = 90

    private static func keep(_ engine: LocalOnlyWhisper, folder: String) {
        let generation = engineCache.put(engine, folder: folder)
        Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: engineIdleSeconds * 1_000_000_000)
            if let idle = engineCache.evict(ifGeneration: generation) { await idle.unloadModels() }
        }
    }

    /// Unloads the cached speech engine. Called before diarization or a language model
    /// loads, so two large models are never resident together.
    static func releaseCachedEngine() async {
        if let engine = engineCache.evict() { await engine.unloadModels() }
    }

    /// Encodes the vocabulary prompt with the engine tokenizer. Returns nil when the tokenizer is unavailable.
    private static func promptTokens(engine: LocalOnlyWhisper, vocabulary: SpeechVocabulary?,
                                     languageCode: String?) -> [Int]? {
        guard let vocabulary = vocabulary, let tokenizer = engine.tokenizer else { return nil }
        let text = " " + vocabulary.promptText(languageCode: languageCode)
        let limit = tokenizer.specialTokens.specialTokenBegin
        let ids = tokenizer.encode(text: text).filter { $0 < limit }
        guard !ids.isEmpty else { return nil }
        return Array(ids.prefix(SpeechVocabulary.maxPromptTokens))
    }

    private static func decode(engine: LocalOnlyWhisper, audio: URL, language: String?,
                               prompt: [Int]?) async throws -> (turns: [AnalysisTurn], language: String?) {
        var options = DecodingOptions(task: .transcribe, language: language,
            usePrefillPrompt: true, detectLanguage: language == nil,
            skipSpecialTokens: true, wordTimestamps: true, concurrentWorkerCount: 1)
        options.promptTokens = prompt
        let results = try await engine.transcribe(audioPath: audio.path,
            audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental(chunkDurationSeconds: 30, maxBufferedChunks: 1)),
            decodeOptions: options,
            callback: { _ in !Task.isCancelled })
        var turns: [AnalysisTurn] = []
        for segment in results.flatMap(\.segments) {
            turns.append(AnalysisTurn(id: "t\(turns.count + 1)", text: segment.text,
                start: Double(segment.start), end: Double(segment.end), speaker: nil))
        }
        return (turns, results.first?.language)
    }
    static func diarize(audio: URL, folder: URL, expectedSpeakers: Int? = nil) async throws -> [SpeakerSpan] {
        await releaseCachedEngine()
        // All compute units in the foreground. In the background iOS denies the GPU,
        // so only the CPU and Neural Engine are requested.
        let units: MLComputeUnits = ComputeEnvironment.gpuAvailable ? .all : .cpuAndNeuralEngine
        do {
            return try await diarizeOnce(audio: audio, folder: folder, expectedSpeakers: expectedSpeakers,
                                         computeUnits: units)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The app moved to the background mid-run and its GPU work was rejected.
            guard units == .all, !ComputeEnvironment.gpuAvailable else { throw error }
            return try await diarizeOnce(audio: audio, folder: folder, expectedSpeakers: expectedSpeakers,
                                         computeUnits: .cpuAndNeuralEngine)
        }
    }

    private static func diarizeOnce(audio: URL, folder: URL, expectedSpeakers: Int?,
                                    computeUnits: MLComputeUnits) async throws -> [SpeakerSpan] {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
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
        // The former batch size of four underutilized the Neural Engine on modern
        // iPhones and made speaker processing the dominant post-recording delay.
        // Eight keeps the peak bounded while materially increasing Core ML throughput.
        config.segmentation.batchSize = 8
        config.embedding.batchSize = 8
        func run(_ settings: OfflineDiarizerConfig) async throws -> [SpeakerSpan] {
            let manager = OfflineDiarizerManager(config: settings)
            manager.initialize(models: models)
            let result = try await manager.process(audio)
            try Task.checkCancellation()
            return result.segments.map { SpeakerSpan(speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds)) }
        }
        // Named attendees give the expected voice count. Small counts are a reliable target; larger
        // groups only cap the count because some attendees may never speak.
        guard let expected = expectedSpeakers, expected >= 2 else { return try await run(config) }
        var constrained = config
        if expected <= 3 { constrained.clustering.numSpeakers = expected } else { constrained.clustering.maxSpeakers = expected }
        do {
            return try await run(constrained)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // An unusable speaker-count request must not cost the meeting its speaker labels.
            return try await run(config)
        }
    }
}
