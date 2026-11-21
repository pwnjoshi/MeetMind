import Foundation

/// Names and agenda words used to prime Whisper so attendee names and English loanwords
/// are spelled consistently. Pure value type; encoding to tokens happens in `LocalSpeech`.
struct SpeechVocabulary: Sendable, Equatable {
    static let maxPromptTokens = 60
    static let maxTerms = 8

    var names: [String]
    var terms: [String]

    /// Nil when the meeting has neither named attendees nor agenda words.
    static func make(participants: [String], agenda: String?) -> SpeechVocabulary? {
        var names: [String] = []
        for name in participants {
            let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = cleaned.lowercased()
            if cleaned.isEmpty || lower.hasPrefix("speaker") || lower.hasPrefix("unknown") { continue }
            if !names.contains(cleaned) { names.append(cleaned) }
            if names.count >= 6 { break }
        }
        var terms: [String] = []
        let stop: Set<String> = ["the", "and", "for", "with", "about", "agenda", "meeting", "discuss", "discussion",
                                 "this", "that", "will", "need", "next", "update", "review"]
        if let agenda = agenda {
            let pieces = agenda.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            for piece in pieces {
                let word = String(piece)
                let lower = word.lowercased()
                guard word.count >= 3, !stop.contains(lower), !terms.contains(where: { $0.lowercased() == lower }) else { continue }
                terms.append(word)
                if terms.count >= maxTerms { break }
            }
        }
        if names.isEmpty && terms.isEmpty { return nil }
        return SpeechVocabulary(names: names, terms: terms)
    }

    /// A short neutral context sentence. With Hindi or automatic language it mixes Devanagari and Latin
    /// so Whisper keeps English loanwords in Latin script and names spelled as given.
    func promptText(languageCode: String?) -> String {
        let nameList = names.joined(separator: ", ")
        let termList = terms.joined(separator: ", ")
        if languageCode == "en" {
            var parts: [String] = []
            if !nameList.isEmpty { parts.append("Meeting with " + nameList + ".") }
            if !termList.isEmpty { parts.append("Topics: " + termList + ".") }
            return parts.joined(separator: " ")
        }
        var parts: [String] = []
        if !nameList.isEmpty { parts.append("नमस्ते " + nameList + "।") }
        if !termList.isEmpty { parts.append("आज की meeting में " + termList + " पर बात करते हैं।") }
        parts.append("हाँ, ठीक है।")
        return parts.joined(separator: " ")
    }
}

/// Remembers the language Whisper settled on for one meeting so that separately
/// transcribed gaps and recording windows do not each re-detect a different language.
final class SpeechLanguageMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    var code: String? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func remember(_ code: String) {
        lock.lock()
        stored = code
        lock.unlock()
    }
}

struct SpeechRequest: Sendable {
    var languageCode: String?
    var vocabulary: SpeechVocabulary?
    var memory: SpeechLanguageMemory?
}

enum SpeakerClusterMerge {
    /// Merges the smallest speaker clusters into the temporally nearest other cluster until at most
    /// `expected` remain. Never returns fewer than one speaker. A nil or non-positive count is a no-op.
    static func mergeExcess(_ spans: [SpeakerSpan], expected: Int?) -> [SpeakerSpan] {
        guard let expected = expected, expected >= 1 else { return spans }
        var current = spans
        var guardCount = 0
        while guardCount < 64 {
            guardCount += 1
            var totals: [String: Double] = [:]
            for span in current { totals[span.speaker, default: 0] += max(0, span.end - span.start) }
            guard totals.count > expected, let smallest = totals.min(by: { $0.value < $1.value }) else { break }
            let small = current.filter { $0.speaker == smallest.key }
            let others = current.filter { $0.speaker != smallest.key }
            var votes: [String: Double] = [:]
            for span in small {
                var best: SpeakerSpan?
                var bestGap = Double.greatestFiniteMagnitude
                for other in others {
                    let gap = max(0, max(span.start - other.end, other.start - span.end))
                    if gap < bestGap { bestGap = gap; best = other }
                }
                if let best = best { votes[best.speaker, default: 0] += max(0.001, span.end - span.start) }
            }
            let target = votes.max(by: { $0.value < $1.value })?.key
                ?? totals.filter { $0.key != smallest.key }.max(by: { $0.value < $1.value })?.key
            guard let merged = target else { break }
            current = current.map { $0.speaker == smallest.key ? SpeakerSpan(speaker: merged, start: $0.start, end: $0.end) : $0 }
        }
        return current.sorted { $0.start < $1.start }
    }
}
