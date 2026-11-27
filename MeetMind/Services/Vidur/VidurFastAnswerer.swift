import Foundation
import OfflineEngineKit

/// Picks the transcript sentence to quote for a grounded answer.
public enum VidurFastAnswerer {
    /// The sentence of `text` that shares the most query words. Always a substring of `text`.
    static func bestSentence(in text: String, queryTokens: Set<String>) -> String {
        let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard whole.count > 200 else { return whole }
        var sentences: [String] = []
        var current = ""
        for character in whole {
            current.append(character)
            if ".?!\u{0964}\n".contains(character) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        guard sentences.count > 1 else { return whole }
        var best = sentences[0]
        var bestScore = -1
        for sentence in sentences {
            let score = Set(VidurTokenizer.tokens(sentence)).intersection(queryTokens).count
            if score > bestScore { best = sentence; bestScore = score }
        }
        return best
    }
}
