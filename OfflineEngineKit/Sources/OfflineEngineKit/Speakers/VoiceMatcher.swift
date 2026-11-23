import Foundation

/// Tunable thresholds for naming diarized voices from stored voice profiles.
public struct VoiceMatchConfig: Equatable, Sendable {
    /// Similarity needed to name a voice without asking. Tune on real recordings.
    public static let defaultAutoThreshold: Float = 0.72
    /// Similarity needed to offer a name as "likely".
    public static let defaultSuggestThreshold: Float = 0.55
    /// How far the best person must lead the runner-up for an automatic name.
    public static let defaultMinimumMargin: Float = 0.08
    /// A voice that spoke less than this is never named.
    public static let defaultMinimumSpeechSeconds: Double = 3

    public var autoThreshold: Float
    public var suggestThreshold: Float
    public var minimumMargin: Float
    public var minimumSpeechSeconds: Double

    public init(autoThreshold: Float = VoiceMatchConfig.defaultAutoThreshold,
                suggestThreshold: Float = VoiceMatchConfig.defaultSuggestThreshold,
                minimumMargin: Float = VoiceMatchConfig.defaultMinimumMargin,
                minimumSpeechSeconds: Double = VoiceMatchConfig.defaultMinimumSpeechSeconds) {
        self.autoThreshold = autoThreshold
        self.suggestThreshold = suggestThreshold
        self.minimumMargin = minimumMargin
        self.minimumSpeechSeconds = minimumSpeechSeconds
    }

    public static let standard = VoiceMatchConfig()
}

/// One diarized voice of a meeting.
public struct VoiceCluster: Equatable, Sendable {
    public let label: String
    public let embedding: [Float]
    public let speechSeconds: Double

    public init(label: String, embedding: [Float], speechSeconds: Double) {
        self.label = label
        self.embedding = embedding
        self.speechSeconds = speechSeconds
    }
}

public enum VoiceMatchStatus: String, Codable, Equatable, Sendable {
    /// Confident enough to name the voice. The user can still change it.
    case auto
    /// Offered as "likely"; the user confirms it.
    case suggested
}

public struct VoiceMatch: Codable, Equatable, Sendable {
    public let label: String
    public let personID: UUID
    public let similarity: Float
    /// Lead over the next best person for this voice.
    public let margin: Float
    public let status: VoiceMatchStatus

    public init(label: String, personID: UUID, similarity: Float, margin: Float, status: VoiceMatchStatus) {
        self.label = label
        self.personID = personID
        self.similarity = similarity
        self.margin = margin
        self.status = status
    }
}

public enum VoiceMatcher {
    /// Voices of one meeting with their talk time, from the embeddings the diarizer produced.
    public static func clusters(embeddings: [String: [Float]], spans: [SpeakerSpan]) -> [VoiceCluster] {
        var seconds: [String: Double] = [:]
        for span in spans { seconds[span.speaker, default: 0] += max(0, span.end - span.start) }
        return embeddings.keys.sorted().compactMap { label in
            guard let vector = embeddings[label], let spoken = seconds[label] else { return nil }
            return VoiceCluster(label: label, embedding: vector, speechSeconds: spoken)
        }
    }

    /// Names voices with a one-to-one assignment that maximises total similarity.
    ///
    /// - Parameter attendeeIDs: When set, the meeting's people (and the user) are tried first and may be
    ///   named automatically. People outside the list are then considered for voices still unmatched, but
    ///   only as suggestions and only above the automatic threshold.
    public static func match(clusters: [VoiceCluster], profiles: [VoiceProfile], attendeeIDs: Set<UUID>? = nil,
                             config: VoiceMatchConfig = .standard) -> [VoiceMatch] {
        var voices: [VoiceCluster] = []
        for cluster in clusters where cluster.speechSeconds >= config.minimumSpeechSeconds {
            guard let unit = SpeakerEmbeddingMath.normalized(cluster.embedding) else { continue }
            voices.append(VoiceCluster(label: cluster.label, embedding: unit, speechSeconds: cluster.speechSeconds))
        }
        let known = profiles.filter { !$0.isEmpty }
        guard !voices.isEmpty, !known.isEmpty else { return [] }

        guard let attendeeIDs else {
            return assign(voices, to: known, floor: config.suggestThreshold, mayAutoName: true, config: config)
        }
        let inRoom = known.filter { attendeeIDs.contains($0.personID) }
        let first = assign(voices, to: inRoom, floor: config.suggestThreshold, mayAutoName: true, config: config)
        let taken = Set(first.map(\.label))
        let rest = voices.filter { !taken.contains($0.label) }
        let outside = known.filter { !attendeeIDs.contains($0.personID) }
        let second = assign(rest, to: outside, floor: max(config.autoThreshold, config.suggestThreshold),
                            mayAutoName: false, config: config)
        return first + second
    }

    private static func assign(_ voices: [VoiceCluster], to pool: [VoiceProfile], floor: Float,
                               mayAutoName: Bool, config: VoiceMatchConfig) -> [VoiceMatch] {
        guard !voices.isEmpty, !pool.isEmpty else { return [] }
        var scores = [[Float]](repeating: [Float](repeating: -1, count: pool.count), count: voices.count)
        for row in voices.indices {
            for column in pool.indices {
                scores[row][column] = pool[column].similarity(to: voices[row].embedding) ?? -1
            }
        }
        // Only pairs at or above the floor can win a name. A zero weight means "leave unnamed".
        let weights: [[Double]] = scores.map { rowScores in
            rowScores.map { value in value >= floor ? Double(value) : 0 }
        }
        let chosen = optimalAssignment(weights: weights)
        var matches: [VoiceMatch] = []
        for row in voices.indices {
            guard let column = chosen[row], scores[row][column] >= floor else { continue }
            let score = scores[row][column]
            var runnerUp: Float = 0
            for other in pool.indices where other != column { runnerUp = max(runnerUp, scores[row][other]) }
            let margin = score - runnerUp
            let confident = mayAutoName && score >= config.autoThreshold && margin >= config.minimumMargin
            matches.append(VoiceMatch(label: voices[row].label, personID: pool[column].personID,
                                      similarity: score, margin: margin,
                                      status: confident ? .auto : .suggested))
        }
        return matches
    }

    /// Hungarian algorithm. Returns, per row, the column that maximises the total weight, or nil when the
    /// row is left unassigned. Rows may outnumber columns and zero-weight pairs count as unassigned.
    static func optimalAssignment(weights: [[Double]]) -> [Int?] {
        let rows = weights.count
        guard rows > 0 else { return [] }
        let realColumns = weights[0].count
        guard realColumns > 0 else { return [Int?](repeating: nil, count: rows) }
        // One spare zero-weight column per row lets any row stay unassigned.
        let columns = realColumns + rows
        var cost = [[Double]](repeating: [Double](repeating: 0, count: columns + 1), count: rows + 1)
        for row in 1...rows {
            for column in 1...realColumns { cost[row][column] = -weights[row - 1][column - 1] }
        }
        var rowPotential = [Double](repeating: 0, count: rows + 1)
        var columnPotential = [Double](repeating: 0, count: columns + 1)
        var owner = [Int](repeating: 0, count: columns + 1)
        var way = [Int](repeating: 0, count: columns + 1)
        for row in 1...rows {
            owner[0] = row
            var column0 = 0
            var minimum = [Double](repeating: Double.infinity, count: columns + 1)
            var used = [Bool](repeating: false, count: columns + 1)
            repeat {
                used[column0] = true
                let row0 = owner[column0]
                var delta = Double.infinity
                var column1 = 0
                for column in 1...columns where !used[column] {
                    let current = cost[row0][column] - rowPotential[row0] - columnPotential[column]
                    if current < minimum[column] {
                        minimum[column] = current
                        way[column] = column0
                    }
                    if minimum[column] < delta {
                        delta = minimum[column]
                        column1 = column
                    }
                }
                for column in 0...columns {
                    if used[column] {
                        rowPotential[owner[column]] += delta
                        columnPotential[column] -= delta
                    } else {
                        minimum[column] -= delta
                    }
                }
                column0 = column1
            } while owner[column0] != 0
            repeat {
                let previous = way[column0]
                owner[column0] = owner[previous]
                column0 = previous
            } while column0 != 0
        }
        var result = [Int?](repeating: nil, count: rows)
        for column in 1...realColumns where owner[column] != 0 {
            result[owner[column] - 1] = column - 1
        }
        return result
    }
}
