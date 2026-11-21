import Foundation
import OfflineEngineKit

/// Tier 1: BM25 ranking over transcript turns. No model, so it returns in milliseconds and always
/// quotes the transcript word for word.
public enum VidurFastAnswerer {
    /// Words that describe asking rather than the topic ("what did Rahul say about pricing").
    private static let askingWords: Set<String> = Set(VidurTokenizer.tokens(
        "say said says talk talked mention mentioned told tell bola kaha bole bataya"))
    private static let speechVerbs: Set<String> = [
        "say", "said", "says", "talk", "talked", "mention", "mentioned", "told", "bola", "kaha", "bole", "bataya", "boli"
    ]

    /// People to restrict the search to when the question asks what someone said.
    public static func speakerFilter(question: String, sources: [VidurSourceMeeting]) -> [String] {
        let words = Set(question.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        guard !words.isDisjoint(with: speechVerbs) else { return [] }
        let speakers = Array(Set(sources.flatMap { $0.turns.compactMap(\.speaker) }))
        return VidurIntentRouter.route(question: question, participantNames: speakers).people
    }

    public static func answer(question: String, sources: [VidurSourceMeeting], speakerFilter: [String] = [],
                              limit: Int = 3) -> VidurAnswer? {
        struct Entry { let meeting: VidurSourceMeeting; let turn: VidurSourceTurn }
        var entries: [Entry] = []
        for meeting in sources {
            for turn in meeting.turns {
                if !speakerFilter.isEmpty {
                    guard let speaker = turn.speaker?.lowercased(), speakerFilter.contains(where: { person in
                        let name = person.lowercased()
                        return speaker == name || speaker.contains(name)
                            || speaker.split(separator: " ").first.map(String.init) == name.split(separator: " ").first.map(String.init)
                    }) else { continue }
                }
                entries.append(Entry(meeting: meeting, turn: turn))
            }
        }
        guard !entries.isEmpty, limit > 0 else { return nil }

        let excluded = Set(VidurTokenizer.tokens(speakerFilter.joined(separator: " "))).union(askingWords)
        let queryTokens = VidurTokenizer.tokens(question).filter { !excluded.contains($0) }
        let uniqueQuery = Set(queryTokens)
        guard !uniqueQuery.isEmpty else { return nil }

        let documents = entries.map { VidurTokenizer.tokens($0.turn.text) }
        let hits = VidurBM25.rank(queryTokens: queryTokens, documents: documents, limit: limit * 4)
        guard let top = hits.first else { return nil }

        // A weak overlap (one word out of many) is not an answer. Let the caller say "not found".
        let coverage = Double(Set(documents[top.index]).intersection(uniqueQuery).count) / Double(uniqueQuery.count)
        if uniqueQuery.count >= 3, coverage < 0.34 { return nil }

        var citations: [VidurCitation] = []
        var lines: [String] = []
        var seen = Set<String>()
        let showTitle = sources.count > 1
        for hit in hits where hit.score >= top.score * 0.4 {
            guard citations.count < limit else { break }
            let entry = entries[hit.index]
            let quote = bestSentence(in: entry.turn.text, queryTokens: uniqueQuery)
            guard seen.insert("\(entry.meeting.id)|\(entry.turn.start)|\(quote)").inserted else { continue }
            citations.append(VidurCitation(meetingID: entry.meeting.id, meetingTitle: entry.meeting.title,
                                           timestamp: entry.turn.start, quote: quote, speaker: entry.turn.speaker))
            let who = entry.turn.speaker.map { "\($0): " } ?? ""
            let where_ = showTitle ? "\(entry.meeting.title) " : ""
            lines.append("\u{2022} \(where_)[\(VidurTimecode.string(entry.turn.start))] \(who)\(quote)")
        }
        guard !citations.isEmpty else { return nil }
        let lead = citations.count == 1 ? "Closest moment in the transcript, quoted exactly:"
                                        : "Closest moments in the transcript, quoted exactly:"
        return VidurAnswer(text: lead + "\n" + lines.joined(separator: "\n"), citations: citations, kind: .extractive)
    }

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
