import Foundation

/// Who spoke when, plus one voice embedding per diarized label. The embeddings come from the clustering
/// the diarizer already ran, so they cost no extra model pass.
struct SpeakerDiarizationOutput: Sendable {
    var spans: [SpeakerSpan]
    /// L2-normalised cluster centroids keyed by the span label. Empty when the engine returned none.
    var embeddings: [String: [Float]]

    init(spans: [SpeakerSpan], embeddings: [String: [Float]] = [:]) {
        self.spans = spans
        self.embeddings = embeddings
    }
}
