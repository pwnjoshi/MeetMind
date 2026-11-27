import Foundation

/// What the first decode of one region revealed about its language.
struct RegionLanguageEvidence: Equatable, Sendable {
    /// The language Whisper detected and used, such as "hi", "en" or "ur". Nil when the region produced no text.
    var detected: String?
    /// Mean token probability of the decoded text in 0...1, or nil when unknown.
    var confidence: Float?
    /// Length of the region in seconds.
    var duration: Double
}

/// Chooses "en" or "hi" (or another confident language) for each region of one recording.
/// Pure and deterministic.
enum SpeechLanguageResolver {
    /// Languages Whisper commonly reports for Hindi-English speech. All are decoded as Hindi.
    static let hindiFamily: Set<String> = ["hi", "ur", "pa", "mr", "ne", "sa", "sd", "gu", "bn", "as"]
    /// A detection below this confidence on a short region defers to the neighbouring region.
    static let confidentThreshold: Float = 0.6
    static let shortRegionSeconds: Double = 4.0
    /// Used only when no region and no earlier window gives any usable detection.
    static let fallbackLanguage = "hi"

    /// Lowercased code with the Hindi family folded to "hi". Nil for a missing or empty code.
    static func canonical(_ code: String?) -> String? {
        guard let code = code else { return nil }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return hindiFamily.contains(trimmed) ? "hi" : trimmed
    }

    private static func isConfident(_ evidence: RegionLanguageEvidence) -> Bool {
        (evidence.confidence ?? 1) >= confidentThreshold
    }

    /// One language per region.
    ///
    /// A region keeps its own detection when that is "en" or "hi" and either confident or long. A foreign
    /// detection such as "ms" is kept only when it is confident and the region is long. Any other region
    /// takes the language of the previous region, else of the next region with a firm detection, else
    /// `previous` (the last language of an earlier window), else its own weak detection, else Hindi.
    /// `previous` is only a hint for uncertain regions and never overrides a firm detection.
    static func resolve(_ evidence: [RegionLanguageEvidence], previous: String? = nil) -> [String] {
        let firm: [String?] = evidence.map { item in
            guard let code = canonical(item.detected) else { return nil }
            let long = item.duration >= shortRegionSeconds
            if code == "en" || code == "hi" {
                return (isConfident(item) || long) ? code : nil
            }
            return (isConfident(item) && long) ? code : nil
        }
        var output: [String] = []
        var last = canonical(previous)
        for index in evidence.indices {
            if let own = firm[index] {
                output.append(own)
                last = own
                continue
            }
            var inherited = last
            if inherited == nil || output.isEmpty {
                // The first uncertain region prefers a firm region after it over an old hint.
                if let ahead = firm[(index + 1)...].compactMap({ $0 }).first { inherited = ahead }
            }
            if inherited == nil, let weak = canonical(evidence[index].detected), weak == "en" || weak == "hi" {
                inherited = weak
            }
            let chosen = inherited ?? fallbackLanguage
            output.append(chosen)
            last = chosen
        }
        return output
    }

    /// Whether `used`, the language the first decode ran with, differs from the language chosen for the region.
    static func needsRedecode(used: String?, chosen: String) -> Bool {
        guard let used = used?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !used.isEmpty else {
            return true
        }
        return used != chosen
    }

    /// Mean token probability of segments, weighted by length. Nil when there are no segments.
    static func confidence(avgLogprobs: [(logprob: Double, seconds: Double)]) -> Float? {
        var weight = 0.0
        var total = 0.0
        for item in avgLogprobs {
            let seconds = max(0.05, item.seconds)
            weight += seconds
            total += min(0, item.logprob) * seconds
        }
        guard weight > 0 else { return nil }
        return Float(exp(total / weight))
    }

    // MARK: - Script check

    /// Letter counts by script.
    static func scriptCounts(_ text: String) -> (latin: Int, devanagari: Int, other: Int) {
        var latin = 0, devanagari = 0, other = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            let value = scalar.value
            if (value >= 0x41 && value <= 0x5A) || (value >= 0x61 && value <= 0x7A) || (value >= 0xC0 && value <= 0x24F) {
                latin += 1
            } else if value >= 0x0900 && value <= 0x097F {
                devanagari += 1
            } else {
                other += 1
            }
        }
        return (latin, devanagari, other)
    }

    /// True when decoded text is plainly in the wrong script for the language it was decoded as:
    /// English output that is mostly non-Latin, or Hindi output that is mostly neither Devanagari nor Latin.
    static func scriptContradicts(language: String, text: String) -> Bool {
        let counts = scriptCounts(text)
        let total = counts.latin + counts.devanagari + counts.other
        guard total >= 4 else { return false }
        switch language {
        case "en": return Double(counts.devanagari + counts.other) / Double(total) > 0.5
        case "hi": return Double(counts.other) / Double(total) > 0.5
        default: return false
        }
    }

    /// The other of English and Hindi.
    static func alternate(of language: String) -> String {
        language == "en" ? "hi" : "en"
    }
}
