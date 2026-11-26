import Foundation

/// An English rendering of one transcript turn, stored next to the original. The transcript itself is never
/// rewritten: `source` repeats the original text so a translation is only used while it still matches its turn.
public struct TurnTranslation: Codable, Sendable, Equatable {
    public let turnID: String
    /// The original turn text this translation was made from.
    public let source: String
    public let english: String
    /// Source language code, "hi" for Hindi and Hinglish.
    public let language: String
    /// Id of the model profile that wrote the translation.
    public let model: String

    public init(turnID: String, source: String, english: String, language: String = "hi", model: String) {
        self.turnID = turnID
        self.source = source
        self.english = english
        self.language = language
        self.model = model
    }
}

/// Hindi speech is transcribed in the spoken language, translated to English as text on the device, and the minutes
/// are written from that English "processing transcript". Evidence is always mapped back to the original turn so a
/// quote shown to the user is a substring of what was actually said.
enum TranscriptTranslation {
    // MARK: Which turns, and what to use

    /// Hindi in either script. Pure English turns are never translated.
    static func needsTranslation(_ turn: AnalysisTurn) -> Bool {
        let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && HindiText.looksHindi(text)
    }

    /// The same turns with English text wherever a translation of exactly this text exists.
    static func processingTurns(_ turns: [AnalysisTurn], translations: [TurnTranslation]?) -> [AnalysisTurn] {
        guard let translations, !translations.isEmpty else { return turns }
        var byID: [String: TurnTranslation] = [:]
        for item in translations where byID[item.turnID] == nil { byID[item.turnID] = item }
        return turns.map { turn in
            guard let item = byID[turn.id], item.source == turn.text, !item.english.isEmpty else { return turn }
            return AnalysisTurn(id: turn.id, text: item.english, start: turn.start, end: turn.end, speaker: turn.speaker)
        }
    }

    /// Evidence written against the English text, mapped to the original turn text.
    static func originalEvidence(_ evidence: [SourceEvidence], turns: [AnalysisTurn],
                                 translations: [TurnTranslation]?) -> [SourceEvidence] {
        EvidenceMapper(turns: turns, translations: translations).original(evidence)
    }

    /// The inverse of `originalEvidence`, for a stored result that already holds original quotes.
    static func processingEvidence(_ evidence: [SourceEvidence], turns: [AnalysisTurn],
                                   translations: [TurnTranslation]?) -> [SourceEvidence] {
        EvidenceMapper(turns: turns, translations: translations).processing(evidence)
    }

    // MARK: Validation

    /// The longest English line that is accepted. `translate.gbnf` allows more characters per line than this, so
    /// output the grammar cut off at its own limit is always longer than this and is rejected, never stored.
    static let maxLineLength = 1_000

    private static let metaPhrases = ["translation", "translate", "hindi", "devanagari", "i cannot", "i can't",
                                      "i'm sorry", "i am sorry", "as an ai", "unintelligible", "note:"]

    private static func words(_ text: String) -> [Substring] {
        text.split(whereSeparator: { $0.isWhitespace })
    }

    private static func wordTokens(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    /// A model translation is used only when it is plain English that says what the source says: no leftover
    /// Devanagari, no commentary, no new or missing numbers, and no attendee name the speaker did not say.
    /// Returns the trimmed English, or nil when the line cannot be trusted.
    static func validated(source: String, english: String, participants: [String]) -> String? {
        let trimmed = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLineLength, !HindiText.containsDevanagari(trimmed) else { return nil }
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return nil }
        let latin = letters.filter { $0.value < 0x250 }.count
        guard Double(latin) / Double(letters.count) >= 0.8 else { return nil }

        let sourceCount = words(source).count
        let englishCount = words(trimmed).count
        guard englishCount >= 1, sourceCount >= 1 else { return nil }
        let upper = max(6, sourceCount * 3)
        // A translation much shorter than a longer source has lost content, so the floor is higher there.
        let floor = sourceCount >= 6 ? 0.4 : 0.25
        let lower = sourceCount >= 3 ? Int((Double(sourceCount) * floor).rounded(.up)) : 1
        guard englishCount <= upper, englishCount >= lower else { return nil }

        let lowerEnglish = trimmed.lowercased()
        let romanSource = HindiRomanizer.romanize(source).lowercased() + " " + source.lowercased()
        for phrase in metaPhrases where lowerEnglish.contains(phrase) && !romanSource.contains(phrase) {
            return nil
        }

        guard TranscriptNumbers.accepts(english: trimmed, source: source) else { return nil }

        let sourceTokens = wordTokens(source) + wordTokens(HindiRomanizer.romanize(source))
        let englishTokens = Set(wordTokens(trimmed).map { $0.lowercased() })
        for participant in participants {
            guard let first = participant.split(separator: " ").first.map(String.init), first.count >= 3 else { continue }
            guard englishTokens.contains(first.lowercased()) else { continue }
            let said = sourceTokens.contains { token in
                token.lowercased() == first.lowercased() || HindiText.namesMatch(token, first)
            }
            if !said { return nil }
        }
        return trimmed
    }

    // MARK: Splitting turns that were fitted to the model

    /// Fitting may halve a long turn into `id.0` and `id.1`. The pieces of the English text were cut for the
    /// model. The original text is cut at the same proportions, at a whitespace boundary where there is one, so the
    /// original pieces concatenate to the original text, and each piece gets its own translation entry.
    static func reconcile(original: [AnalysisTurn], fitted: [AnalysisTurn], translations: [TurnTranslation]?,
                          model: String) -> (turns: [AnalysisTurn], translations: [TurnTranslation]?) {
        guard let translations, !translations.isEmpty else { return (fitted, translations) }
        var originalByID: [String: AnalysisTurn] = [:]
        for turn in original where originalByID[turn.id] == nil { originalByID[turn.id] = turn }
        var translationByID: [String: TurnTranslation] = [:]
        for item in translations where translationByID[item.turnID] == nil { translationByID[item.turnID] = item }
        let identifiers = originalByID.keys.sorted { $0.count > $1.count }

        func base(of id: String) -> AnalysisTurn? {
            guard originalByID[id] == nil else { return nil }
            guard let found = identifiers.first(where: { id.hasPrefix($0 + ".") }) else { return nil }
            return originalByID[found]
        }
        var groups: [String: [AnalysisTurn]] = [:]
        for turn in fitted {
            guard let parent = base(of: turn.id), let item = translationByID[parent.id], item.source == parent.text
            else { continue }
            groups[parent.id, default: []].append(turn)
        }
        var replacement: [String: AnalysisTurn] = [:]
        var added: [TurnTranslation] = []
        for parentID in groups.keys.sorted() {
            guard let pieces = groups[parentID], let parent = originalByID[parentID] else { continue }
            let lengths = pieces.map { $0.text.count }
            let cuts = cutPoints(of: parent.text, proportions: lengths)
            for (index, piece) in pieces.enumerated() {
                let text = cuts[index]
                replacement[piece.id] = AnalysisTurn(id: piece.id, text: text, start: piece.start, end: piece.end,
                                                     speaker: piece.speaker)
                if !text.isEmpty {
                    added.append(TurnTranslation(turnID: piece.id, source: text, english: piece.text,
                                                 language: translationByID[parentID]?.language ?? "hi", model: model))
                }
            }
        }
        let turns = fitted.map { originalByID[$0.id] ?? replacement[$0.id] ?? $0 }
        let ids = Set(turns.map(\.id))
        let kept = translations.filter { ids.contains($0.turnID) }
        return (turns, kept + added.filter { ids.contains($0.turnID) })
    }

    /// Cuts `text` into one piece per weight, in proportion to the weights. Pieces concatenate to `text`.
    static func cutPoints(of text: String, proportions weights: [Int]) -> [String] {
        let characters = Array(text)
        let total = max(1, weights.reduce(0, +))
        var boundaries: [Int] = []
        var cumulative = 0
        var previous = 0
        for (index, weight) in weights.enumerated() {
            cumulative += weight
            if index == weights.count - 1 { boundaries.append(characters.count); break }
            var target = Int((Double(cumulative) / Double(total) * Double(characters.count)).rounded())
            target = min(max(target, previous), characters.count)
            var chosen = target
            let window = max(8, characters.count / 10)
            search: for distance in 0...window {
                for candidate in [target - distance, target + distance] {
                    if candidate > previous, candidate < characters.count, characters[candidate - 1].isWhitespace {
                        chosen = candidate
                        break search
                    }
                }
            }
            boundaries.append(chosen)
            previous = chosen
        }
        var pieces: [String] = []
        var start = 0
        for end in boundaries {
            pieces.append(String(characters[start..<max(start, end)]))
            start = max(start, end)
        }
        return pieces
    }

    // MARK: Provenance note

    /// What the reader is told about machine translation. Nil when no translation stage ran.
    static func languageNote(turns: [AnalysisTurn], translations: [TurnTranslation]?) -> String? {
        guard let translations else { return nil }
        let byID = Dictionary(turns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let usedIDs = Set(translations.compactMap { item -> String? in
            guard let turn = byID[item.turnID], turn.text == item.source, !item.english.isEmpty else { return nil }
            return turn.id
        })
        let translated = usedIDs.count
        let failed = turns.filter { !usedIDs.contains($0.id) && needsTranslation($0) }.count
        var parts: [String] = []
        if translated > 0 {
            parts.append("Hindi speech in \(translated) of \(turns.count) transcript lines was machine-translated to English on this iPhone to write these minutes. Quotes show the original words.")
        }
        if failed > 0 {
            let noun = failed == 1 ? "Hindi line" : "Hindi lines"
            let verb = failed == 1 ? "was" : "were"
            parts.append("\(failed) \(noun) could not be translated reliably and \(verb) only checked with the Hindi phrase rules.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// Converts evidence between the original transcript and the English processing transcript.
struct EvidenceMapper {
    private struct Entry {
        let original: String
        let english: String
    }
    private let entries: [String: Entry]

    init(turns: [AnalysisTurn], translations: [TurnTranslation]?) {
        var table: [String: Entry] = [:]
        if let translations {
            let byID = Dictionary(turns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for item in translations where table[item.turnID] == nil {
                guard let turn = byID[item.turnID], item.source == turn.text, !item.english.isEmpty else { continue }
                table[item.turnID] = Entry(original: turn.text, english: item.english)
            }
        }
        entries = table
    }

    var isIdentity: Bool { entries.isEmpty }

    /// Maps a quote between two renderings of one turn. When both split into the same number of sentences the
    /// matching sentence is used, otherwise the whole turn.
    private func remap(_ quote: String, from: String, to: String) -> String {
        let source = PromptNormalizer.pieces(of: from)
        let target = PromptNormalizer.pieces(of: to)
        if source.count == target.count, source.count > 1,
           let index = source.firstIndex(where: { $0.contains(quote) }) {
            let piece = target[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { return piece }
        }
        let whole = to.trimmingCharacters(in: .whitespacesAndNewlines)
        return whole.isEmpty ? quote : whole
    }

    func original(_ evidence: [SourceEvidence]) -> [SourceEvidence] {
        guard !entries.isEmpty else { return evidence }
        return evidence.map { item in
            guard let entry = entries[item.turnID], !item.quote.isEmpty, entry.english.contains(item.quote) else { return item }
            if entry.original.contains(item.quote) { return item }
            return SourceEvidence(turnID: item.turnID, quote: remap(item.quote, from: entry.english, to: entry.original))
        }
    }

    func processing(_ evidence: [SourceEvidence]) -> [SourceEvidence] {
        guard !entries.isEmpty else { return evidence }
        return evidence.map { item in
            guard let entry = entries[item.turnID], !item.quote.isEmpty, entry.original.contains(item.quote),
                  !entry.english.contains(item.quote) else { return item }
            return SourceEvidence(turnID: item.turnID, quote: remap(item.quote, from: entry.original, to: entry.english))
        }
    }

    // MARK: Whole structures

    private func points(_ values: [SupportedPoint], _ transform: ([SourceEvidence]) -> [SourceEvidence]) -> [SupportedPoint] {
        values.map { SupportedPoint(text: $0.text, evidence: transform($0.evidence)) }
    }

    private func result(_ value: LocalAnalysisResult, _ transform: ([SourceEvidence]) -> [SourceEvidence]) -> LocalAnalysisResult {
        let tasks = value.tasks.map {
            SuggestedTask(title: $0.title, category: $0.category, owner: $0.owner, deadlineText: $0.deadlineText,
                          priority: $0.priority, evidence: transform($0.evidence))
        }
        return LocalAnalysisResult(discussion: points(value.discussion, transform),
                                   decisions: points(value.decisions, transform), tasks: tasks,
                                   openIssues: points(value.openIssues, transform))
    }

    func processing(_ value: LocalAnalysisResult) -> LocalAnalysisResult {
        entries.isEmpty ? value : result(value) { (e: [SourceEvidence]) in self.processing(e) }
    }

    func original(_ value: LocalAnalysisResult) -> LocalAnalysisResult {
        entries.isEmpty ? value : result(value) { (e: [SourceEvidence]) in self.original(e) }
    }

    func original(_ values: [SupportedPoint]) -> [SupportedPoint] {
        entries.isEmpty ? values : points(values) { (e: [SourceEvidence]) in self.original(e) }
    }

    func original(_ values: [SuggestedTask]) -> [SuggestedTask] {
        guard !entries.isEmpty else { return values }
        return values.map {
            SuggestedTask(title: $0.title, category: $0.category, owner: $0.owner, deadlineText: $0.deadlineText,
                          priority: $0.priority, evidence: original($0.evidence))
        }
    }

    func original(_ minutes: MinutesContent) -> MinutesContent {
        guard !entries.isEmpty else { return minutes }
        let topics = minutes.topics.map {
            MinutesTopic(title: $0.title, discussion: $0.discussion, outcome: $0.outcome, evidence: original($0.evidence),
                         timestamp: $0.timestamp, speaker: $0.speaker)
        }
        let resolutions = minutes.resolutions.map {
            MinutesResolution(text: $0.text, rationale: $0.rationale, topic: $0.topic, evidence: original($0.evidence),
                              timestamp: $0.timestamp, speaker: $0.speaker)
        }
        let actions = minutes.actions.map {
            MinutesAction(title: $0.title, owner: $0.owner, deadlineText: $0.deadlineText, dueDate: $0.dueDate,
                          topic: $0.topic, evidence: original($0.evidence), timestamp: $0.timestamp, speaker: $0.speaker)
        }
        let issues = minutes.openIssues.map {
            MinutesOpenIssue(text: $0.text, subject: $0.subject, topic: $0.topic, nextMeeting: $0.nextMeeting,
                             evidence: original($0.evidence), timestamp: $0.timestamp, speaker: $0.speaker)
        }
        let attendees = minutes.suggestedAttendees.map {
            SuggestedAttendee(name: $0.name, reason: $0.reason, evidence: original($0.evidence))
        }
        let next = minutes.nextMeeting.map {
            MinutesNextMeeting(text: $0.text, dateText: $0.dateText, timeText: $0.timeText, isoDate: $0.isoDate,
                               evidence: original($0.evidence))
        }
        let statements = minutes.summaryStatements.map {
            MinutesSummaryStatement(text: $0.text, evidence: original($0.evidence))
        }
        var mapped = MinutesContent(executiveSummary: minutes.executiveSummary, topics: topics, resolutions: resolutions,
                                    actions: actions, openIssues: issues, suggestedAttendees: attendees,
                                    nextMeeting: next, summaryStatements: statements)
        mapped.languageNote = minutes.languageNote
        return mapped
    }
}
