import Foundation
import WhisperKit
import FluidAudio
import CoreML
import AVFoundation
import os

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
    private static let log = os.Logger(subsystem: "OfflineEngineKit", category: "speech")

    /// Regions shorter than this many samples (0.2 s at 16 kHz) are skipped as noise.
    private static let minimumRegionSamples = 3_200
    /// Whisper does not decode a window shorter than its one-second end guard, so shorter regions are
    /// padded with silence up to this many samples (1.5 s).
    private static let paddedRegionSamples = 24_000

    /// Transcribes one recording or window.
    ///
    /// An explicit `languageCode` ("en", "hi", ...) decodes the whole file in that language. A nil code
    /// (Hindi + English or automatic) splits the audio into speech regions and decodes each region in its
    /// own language, so an English sentence is written in Latin letters and a Hindi sentence in Devanagari.
    /// `memory` only hints the language of an uncertain first region; it never forces a language.
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
            var run = SpeechDecodeStats()
            run.runs = 1
            let turns: [AnalysisTurn]
            if let fixed = languageCode, !fixed.isEmpty {
                turns = try await transcribeWholeFile(engine: engine, audio: audio, fixedLanguage: fixed,
                                                      vocabulary: vocabulary, memory: memory, stats: &run)
            } else if let regional = try await transcribeRegions(engine: engine, audio: audio, vocabulary: vocabulary,
                                                                 memory: memory, stats: &run) {
                turns = regional
            } else {
                turns = try await transcribeWholeFile(engine: engine, audio: audio, fixedLanguage: nil,
                                                      vocabulary: vocabulary, memory: memory, stats: &run)
            }
            SpeechDiagnostics.record(run)
            log.info("\(run.description, privacy: .public)")
            try Task.checkCancellation()
            // Live recording windows arrive every 30 seconds and the final pass follows
            // soon after Stop, so the loaded engine is kept briefly instead of reloaded.
            keep(engine, folder: folder.path)
            return turns
        } catch {
            await engine.unloadModels()
            throw error
        }
    }

    // MARK: - Whole-file decode

    /// One decode of the whole file. With `fixedLanguage` nil Whisper detects the language once per
    /// 30-second window and a result other than Hindi or English is decoded again as Hindi. This is the
    /// fallback when region planning finds no speech or cannot read the file.
    private static func transcribeWholeFile(engine: LocalOnlyWhisper, audio: URL, fixedLanguage: String?,
                                            vocabulary: SpeechVocabulary?, memory: SpeechLanguageMemory?,
                                            stats: inout SpeechDecodeStats) async throws -> [AnalysisTurn] {
        stats.wholeFileRuns += 1
        let started = Date()
        defer { stats.decodeSeconds += Date().timeIntervalSince(started) }
        let prompt = promptTokens(engine: engine, vocabulary: vocabulary, languageCode: fixedLanguage)
        var pass = try await decode(engine: engine, audio: audio, language: fixedLanguage, prompt: prompt)
        guard fixedLanguage == nil else { return pass.turns }
        stats.detections += 1
        let detected = (pass.language ?? "").lowercased()
        var language = detected
        if !detected.isEmpty, detected != "hi", detected != "en" {
            pass = try await decode(engine: engine, audio: audio, language: "hi", prompt: prompt)
            stats.redecodes += 1
            language = "hi"
        }
        if language == "hi" || language == "en" { memory?.remember(language) }
        return pass.turns
    }

    // MARK: - Per-region decode

    private struct RegionPass {
        var region: SpeechRegion
        /// Region-relative turns.
        var turns: [AnalysisTurn]
        /// The language the decode ran with.
        var used: String?
        var confidence: Float?
    }

    private struct RegionDecode {
        var turns: [AnalysisTurn]
        var language: String?
        var confidence: Float?
    }

    /// Splits the audio into speech regions, decodes each with automatic language detection (one encoder
    /// pass per region, detection reuses that pass), resolves one language per region with hysteresis,
    /// and decodes again only the regions whose language was corrected. Returns nil when there is nothing
    /// to split, so the caller falls back to the whole-file decode.
    private static func transcribeRegions(engine: LocalOnlyWhisper, audio: URL, vocabulary: SpeechVocabulary?,
                                          memory: SpeechLanguageMemory?,
                                          stats: inout SpeechDecodeStats) async throws -> [AnalysisTurn]? {
        let planStarted = Date()
        let regions: [SpeechRegion]
        let duration: Double
        do {
            let plan = try planRegions(audio: audio)
            regions = plan.regions
            duration = plan.duration
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
        stats.planSeconds += Date().timeIntervalSince(planStarted)
        stats.audioSeconds += duration
        guard !regions.isEmpty else { return nil }

        let path = audio.path
        let automaticPrompt = promptTokens(engine: engine, vocabulary: vocabulary, languageCode: nil)
        var passes: [RegionPass] = []
        for region in regions {
            try Task.checkCancellation()
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: path, startTime: region.start,
                                                                   endTime: region.end)
            guard samples.count >= minimumRegionSamples else {
                passes.append(RegionPass(region: region, turns: [], used: nil, confidence: nil))
                continue
            }
            let started = Date()
            let first = try await decodeRegion(engine: engine, samples: samples, language: nil, prompt: automaticPrompt)
            stats.decodeSeconds += Date().timeIntervalSince(started)
            stats.regions += 1
            stats.detections += 1
            stats.speechSeconds += region.duration
            passes.append(RegionPass(region: region, turns: first.turns, used: first.language,
                                     confidence: first.confidence))
        }

        let evidence = passes.map { pass in
            RegionLanguageEvidence(detected: pass.turns.isEmpty ? nil : pass.used, confidence: pass.confidence,
                                   duration: pass.region.duration)
        }
        var languages = SpeechLanguageResolver.resolve(evidence, previous: memory?.code)

        for index in passes.indices where !passes[index].turns.isEmpty {
            var target = languages[index]
            var redo = SpeechLanguageResolver.needsRedecode(used: passes[index].used, chosen: target)
            if !redo {
                let text = passes[index].turns.map { $0.text }.joined(separator: " ")
                if SpeechLanguageResolver.scriptContradicts(language: target, text: text) {
                    target = SpeechLanguageResolver.alternate(of: target)
                    languages[index] = target
                    redo = true
                }
            }
            guard redo else { continue }
            try Task.checkCancellation()
            let region = passes[index].region
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: path, startTime: region.start,
                                                                   endTime: region.end)
            let started = Date()
            let again = try await decodeRegion(engine: engine, samples: samples, language: target,
                prompt: promptTokens(engine: engine, vocabulary: vocabulary, languageCode: target))
            stats.decodeSeconds += Date().timeIntervalSince(started)
            stats.redecodes += 1
            if !again.turns.isEmpty {
                passes[index].turns = again.turns
                passes[index].used = target
            }
        }

        var lastLanguage: String?
        for (language, pass) in zip(languages, passes) where !pass.turns.isEmpty { lastLanguage = language }
        if let lastLanguage = lastLanguage { memory?.remember(lastLanguage) }

        var turns: [AnalysisTurn] = []
        for pass in passes {
            for turn in pass.turns {
                let moved = SpeechRegionPlanner.shifted(start: turn.start, end: turn.end, by: pass.region.start,
                                                        limit: pass.region.duration)
                turns.append(AnalysisTurn(id: "t\(turns.count + 1)", text: turn.text,
                                          start: moved.start, end: moved.end, speaker: nil))
            }
        }
        return turns
    }

    /// Reads the file in one-minute blocks (bounded memory), measures frame energy, and plans regions.
    private static func planRegions(audio: URL) throws -> (regions: [SpeechRegion], duration: Double) {
        let parameters = SpeechRegionPlanner.Parameters.standard
        let file = try AVAudioFile(forReading: audio)
        let rate = file.fileFormat.sampleRate
        guard rate > 0 else { return ([], 0) }
        let duration = Double(file.length) / rate
        guard duration.isFinite, duration > 0 else { return ([], 0) }
        let frameLength = max(1, Int((parameters.frameSeconds * Double(WhisperKit.sampleRate)).rounded()))
        let blockSeconds = 60.0
        var energies: [Float] = []
        var start = 0.0
        while start < duration {
            try Task.checkCancellation()
            let end = min(start + blockSeconds, duration)
            var block: [Float] = []
            try autoreleasepool {
                block = try AudioProcessor.loadAudioAsFloatArray(fromPath: audio.path, startTime: start, endTime: end)
            }
            // Keep every block on the same time grid even when resampling returns a sample more or less.
            let expected = max(1, Int(((end - start) / parameters.frameSeconds).rounded()))
            var frames = SpeechRegionPlanner.frameEnergies(block, frameLength: frameLength)
            if frames.count > expected { frames.removeLast(frames.count - expected) }
            if frames.count < expected { frames.append(contentsOf: [Float](repeating: 0, count: expected - frames.count)) }
            energies.append(contentsOf: frames)
            start = end
        }
        return (SpeechRegionPlanner.plan(energies: energies, parameters: parameters), duration)
    }

    private static func decodeRegion(engine: LocalOnlyWhisper, samples: [Float], language: String?,
                                     prompt: [Int]?) async throws -> RegionDecode {
        var audio = samples
        if audio.count < paddedRegionSamples {
            audio.append(contentsOf: [Float](repeating: 0, count: paddedRegionSamples - audio.count))
        }
        var options = DecodingOptions(task: .transcribe, language: language,
            usePrefillPrompt: true, detectLanguage: language == nil,
            skipSpecialTokens: true, wordTimestamps: true, concurrentWorkerCount: 1)
        options.promptTokens = prompt
        let results = try await engine.transcribe(audioArray: audio, decodeOptions: options,
                                                  callback: { _ in !Task.isCancelled })
        var turns: [AnalysisTurn] = []
        var logprobs: [(logprob: Double, seconds: Double)] = []
        for segment in results.flatMap(\.segments) {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            turns.append(AnalysisTurn(id: "r\(turns.count + 1)", text: segment.text,
                                      start: Double(segment.start), end: Double(segment.end), speaker: nil))
            logprobs.append((Double(segment.avgLogprob), Double(segment.end - segment.start)))
        }
        let detected = turns.isEmpty ? nil : results.first?.language
        return RegionDecode(turns: turns, language: detected,
                            confidence: SpeechLanguageResolver.confidence(avgLogprobs: logprobs))
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
