import Foundation

/// Vector helpers for speaker embeddings (the diarization model's 256-dim voice vectors).
public enum SpeakerEmbeddingMath {
    /// The vector scaled to unit length, or nil when it is empty, has a non-finite value or has no length.
    public static func normalized(_ vector: [Float]) -> [Float]? {
        guard !vector.isEmpty else { return nil }
        var sum: Double = 0
        for value in vector {
            guard value.isFinite else { return nil }
            sum += Double(value) * Double(value)
        }
        let length = sum.squareRoot()
        guard length > 1e-6 else { return nil }
        let scale = Float(1 / length)
        return vector.map { $0 * scale }
    }

    /// Cosine similarity in [-1, 1], or nil when the vectors cannot be compared.
    public static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float? {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return nil }
        var dot: Double = 0
        var leftSquares: Double = 0
        var rightSquares: Double = 0
        for index in lhs.indices {
            let left = Double(lhs[index])
            let right = Double(rhs[index])
            guard left.isFinite, right.isFinite else { return nil }
            dot += left * right
            leftSquares += left * left
            rightSquares += right * right
        }
        let denominator = (leftSquares * rightSquares).squareRoot()
        guard denominator > 1e-12 else { return nil }
        return Float(max(-1, min(1, dot / denominator)))
    }
}

/// What the app remembers about one person's voice: embeddings only, never audio.
public struct VoiceProfile: Codable, Equatable, Sendable {
    /// Most exemplar embeddings kept besides the running mean.
    public static let maxExemplars = 5
    /// A new embedding less similar than this to the person's mean is not their voice, so it is not learned.
    public static let outlierSimilarity: Float = 0.4
    /// The running mean counts at most this many past samples, so a profile keeps adapting.
    public static let maxWeight = 12
    /// An embedding this close to a stored exemplar replaces it instead of taking another slot.
    public static let duplicateSimilarity: Float = 0.97

    public enum LearnResult: Equatable, Sendable {
        case created, updated, rejectedOutlier, rejectedInvalid
    }

    public let personID: UUID
    /// L2-normalised running mean. Empty until the first sample is learned.
    public private(set) var centroid: [Float]
    public private(set) var exemplars: [[Float]]
    public private(set) var sampleCount: Int
    public private(set) var updatedAt: Date

    public init(personID: UUID, updatedAt: Date = Date()) {
        self.personID = personID
        self.centroid = []
        self.exemplars = []
        self.sampleCount = 0
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool { centroid.isEmpty }

    /// Folds one voice embedding into the profile.
    @discardableResult
    public mutating func learn(_ embedding: [Float], now: Date = Date()) -> LearnResult {
        guard let sample = SpeakerEmbeddingMath.normalized(embedding) else { return .rejectedInvalid }
        if centroid.isEmpty {
            centroid = sample
            exemplars = [sample]
            sampleCount = 1
            updatedAt = now
            return .created
        }
        guard sample.count == centroid.count else { return .rejectedInvalid }
        guard let similarity = SpeakerEmbeddingMath.cosine(sample, centroid),
              similarity >= Self.outlierSimilarity else { return .rejectedOutlier }
        let weight = Float(min(max(sampleCount, 1), Self.maxWeight))
        var blended = centroid
        for index in blended.indices { blended[index] = blended[index] * weight + sample[index] }
        guard let merged = SpeakerEmbeddingMath.normalized(blended) else { return .rejectedInvalid }
        centroid = merged
        sampleCount += 1
        if let index = exemplars.firstIndex(where: {
            (SpeakerEmbeddingMath.cosine($0, sample) ?? 0) >= Self.duplicateSimilarity
        }) {
            exemplars[index] = sample
        } else {
            exemplars.append(sample)
            if exemplars.count > Self.maxExemplars { exemplars.removeFirst(exemplars.count - Self.maxExemplars) }
        }
        updatedAt = now
        return .updated
    }

    /// How closely `embedding` matches this person: 60% the mean voice, 40% the best exemplar.
    public func similarity(to embedding: [Float]) -> Float? {
        guard !centroid.isEmpty, let sample = SpeakerEmbeddingMath.normalized(embedding),
              let mean = SpeakerEmbeddingMath.cosine(sample, centroid) else { return nil }
        let best = exemplars.compactMap { SpeakerEmbeddingMath.cosine(sample, $0) }.max() ?? mean
        return 0.6 * mean + 0.4 * best
    }
}
