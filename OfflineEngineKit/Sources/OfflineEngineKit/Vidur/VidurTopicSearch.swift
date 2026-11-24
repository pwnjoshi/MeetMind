import Foundation

/// Hybrid search over minutes items and transcript turns. Works across scripts: an English question
/// matches Devanagari text through consonant skeletons and a small English/Hindi concept list.
enum VidurTopicSearch {
    private struct Doc {
        let record: VidurMeetingRecord
        let label: String?
        let text: String
        let quote: String
        let timestamp: TimeInterval?
        let speaker: String?
        let keys: [String]
        let weight: Double
    }

    private struct Hit {
        let doc: Doc
        let score: Double
        let coverage: Double
    }

    private static func docs(_ context: VidurQuickContext) -> [Doc] {
        let people = context.parsed.people
        let index = context.index
        func speakerMatches(_ raw: String?) -> Bool {
            people.isEmpty || people.contains { index.matches(raw, $0) }
        }
        func mentionsPerson(_ text: String) -> Bool {
            people.isEmpty || people.contains { index.mentions(text, $0) }
        }
        var output: [Doc] = []
        for record in context.records {
            if people.isEmpty {
                let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !summary.isEmpty {
                    output.append(Doc(record: record, label: "Summary", text: summary, quote: summary, timestamp: nil,
                                      speaker: nil, keys: VidurScript.keys(summary), weight: 1.0))
                }
                for line in record.discussion where line != summary && !line.isEmpty {
                    output.append(Doc(record: record, label: "Discussion", text: line, quote: line, timestamp: nil,
                                      speaker: nil, keys: VidurScript.keys(line), weight: 1.1))
                }
                for line in record.agenda where !line.isEmpty {
                    output.append(Doc(record: record, label: "Agenda", text: line, quote: line, timestamp: nil,
                                      speaker: nil, keys: VidurScript.keys(line), weight: 0.5))
                }
            }
            for line in record.decisions where speakerMatches(line.speaker) || mentionsPerson(line.text) {
                output.append(Doc(record: record, label: "Decision", text: line.text, quote: line.quote ?? line.text,
                                  timestamp: line.timestamp, speaker: line.speaker,
                                  keys: VidurScript.keys(line.text + " " + (line.quote ?? "")), weight: 1.4))
            }
            for line in record.openIssues where speakerMatches(line.speaker) || mentionsPerson(line.text) {
                output.append(Doc(record: record, label: "Open issue", text: line.text, quote: line.quote ?? line.text,
                                  timestamp: line.timestamp, speaker: line.speaker,
                                  keys: VidurScript.keys(line.text + " " + (line.quote ?? "")), weight: 1.3))
            }
            for task in record.tasks where people.isEmpty || people.contains(where: { index.matches(task.owner, $0) }) {
                var text = task.title
                if let owner = task.owner, !owner.isEmpty {
                    text += " (" + (index.person(forRaw: owner)?.canonical ?? owner)
                    if let due = task.dueDate { text += ", due " + context.dueDay(due) }
                    else if let dueText = task.dueText, !dueText.isEmpty { text += ", due " + dueText }
                    text += ")"
                }
                output.append(Doc(record: record, label: "Action", text: text, quote: task.quote ?? task.title,
                                  timestamp: task.timestamp, speaker: nil,
                                  keys: VidurScript.keys(task.title + " " + (task.quote ?? "")), weight: 1.3))
            }
            for turn in record.turns where speakerMatches(turn.speaker) {
                let isNote = turn.speaker == "Note"
                output.append(Doc(record: record, label: isNote ? "Note" : nil, text: turn.text, quote: turn.text,
                                  timestamp: turn.start, speaker: isNote ? nil : turn.speaker,
                                  keys: VidurScript.keys(turn.text), weight: 1.0))
            }
        }
        return output
    }

    /// Returns a section when the minutes or transcript talk about the topic words of the question.
    static func search(_ context: VidurQuickContext, original: VidurParsedQuestion) -> VidurSection? {
        let terms = context.topicTerms
        let people = context.parsed.people
        if terms.isEmpty {
            return people.isEmpty ? nil : personDigest(context)
        }
        let documents = docs(context)
        guard !documents.isEmpty else { return nil }
        let flat = Array(Set(terms.flatMap { $0 }))
        let ranked = VidurBM25.rank(queryTokens: flat, documents: documents.map(\.keys), limit: documents.count)
        let need = max(1, Int((Double(terms.count) * 0.5).rounded(.up)))
        var hits: [Hit] = []
        for hit in ranked {
            let doc = documents[hit.index]
            let keySet = Set(doc.keys)
            let matched = terms.filter { !keySet.isDisjoint(with: $0) }.count
            guard matched >= need else { continue }
            let coverage = Double(matched) / Double(terms.count)
            hits.append(Hit(doc: doc, score: hit.score * doc.weight * (0.5 + 0.5 * coverage), coverage: coverage))
        }
        guard !hits.isEmpty else { return nil }
        hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.doc.record.date > $1.doc.record.date }

        var chosen: [Hit] = []
        var minutesCount = 0
        var transcriptCount = 0
        for hit in hits {
            guard chosen.count < 3 else { break }
            let isMinutes = hit.doc.label != nil && hit.doc.label != "Note"
            if isMinutes, minutesCount >= 2 { continue }
            if !isMinutes, transcriptCount >= 2 { continue }
            let duplicate = chosen.contains { other in
                other.doc.record.id == hit.doc.record.id && other.doc.label == hit.doc.label
                    && other.doc.timestamp == hit.doc.timestamp && other.doc.text == hit.doc.text
            }
            if duplicate { continue }
            chosen.append(hit)
            if isMinutes { minutesCount += 1 } else { transcriptCount += 1 }
        }
        guard let top = chosen.first else { return nil }

        let queryKeys = Set(flat)
        let topicText = context.parsed.residual.joined(separator: " ")
        let multiple = Set(chosen.map { $0.doc.record.id }).count > 1 || context.isMultiple
        func place(_ hit: Hit) -> String {
            multiple ? "\(VidurQuickContext.title(hit.doc.record)), \(context.day(hit.doc.record.date))"
                     : VidurQuickContext.title(hit.doc.record)
        }
        func line(_ hit: Hit, standalone: Bool) -> String {
            let doc = hit.doc
            if let label = doc.label, label != "Note" {
                let body = VidurQuickContext.excerpt(doc.text, keys: queryKeys)
                return standalone ? "\(label) in \(context.label(doc.record)): \(body)"
                                  : "\u{2022} \(label) (\(place(hit))): \(body)"
            }
            let quote = VidurQuickContext.excerpt(doc.text, keys: queryKeys)
            let stamp = doc.timestamp.map { VidurQuickContext.timecode($0) } ?? ""
            let who = context.displayName(doc.speaker)
            if standalone {
                if original.whoSaid, let who {
                    return "\(who) said this in \(context.label(doc.record)) at \(stamp): \u{201C}\(quote)\u{201D}"
                }
                if let who { return "In \(context.label(doc.record)), \(who) said: \u{201C}\(quote)\u{201D} (\(stamp))" }
                return "A note in \(context.label(doc.record)) says: \u{201C}\(quote)\u{201D}"
            }
            return "\u{2022} \(who ?? "Note") (\(place(hit)), \(stamp)): \u{201C}\(quote)\u{201D}"
        }

        let names = context.firstNames
        /// A cautious sentence for a transcript hit, or nil when the line is not plain English.
        func spoken(_ hit: Hit) -> String? {
            let doc = hit.doc
            guard doc.label == nil, doc.text.unicodeScalars.allSatisfy({ $0.isASCII }),
                  VidurAnswerLanguage.detect(doc.text) == .english else { return nil }
            let day = context.day(doc.record.date)
            let who = context.speakerWord(doc.speaker)
            if let clause = VidurGist.clause(from: doc.text, topicKeys: queryKeys, names: names) {
                let wording = VidurSpokenDates.prefer(clause, record: doc.record)
                return "On \(day), \(who) said that \(wording)."
            }
            return "On \(day), \(who) talked about \(topicText)."
        }
        func lowercasedFirst(_ sentence: String) -> String {
            String(sentence.prefix(1)).lowercased() + String(sentence.dropFirst())
        }
        func isSame(_ lhs: Hit, _ rhs: Hit) -> Bool {
            lhs.doc.record.id == rhs.doc.record.id && lhs.doc.timestamp == rhs.doc.timestamp && lhs.doc.text == rhs.doc.text
        }

        let decisionAsked = original.intents.contains(.decisions)
        let ownerAsked = original.intents.contains(.tasks) && original.asksOwner
        var lead: Hit?
        var isSaved = true
        var answersOwner = false
        let text: String
        if ownerAsked, let found = ownerSentence(hits: hits, context: context, keys: queryKeys, topic: topicText) {
            text = found.text
            lead = found.hit
            isSaved = false
            answersOwner = true
        } else if decisionAsked, top.doc.label == nil, let sentence = spoken(top) {
            text = "There\u{2019}s no recorded decision about \(topicText), but " + lowercasedFirst(sentence)
            isSaved = false
        } else if chosen.count == 1 {
            text = spoken(top) ?? line(top, standalone: true)
        } else {
            let head: String
            if !people.isEmpty {
                head = "Here\u{2019}s what \(people.map(\.canonical).joined(separator: " and ")) said about \(topicText):"
            } else if original.whoSaid {
                head = "Here\u{2019}s who talked about \(topicText):"
            } else {
                head = "Here\u{2019}s what your meetings say about \(topicText):"
            }
            var bullets: [String] = []
            for hit in chosen {
                if let sentence = spoken(hit) {
                    bullets.append("\u{2022} " + sentence)
                } else {
                    bullets.append(line(hit, standalone: false))
                }
            }
            text = head + "\n" + bullets.joined(separator: "\n")
        }

        var shown = chosen
        if let lead {
            shown = [lead] + chosen.filter { !isSame($0, lead) }
            if shown.count > 3 { shown = Array(shown.prefix(3)) }
        }
        var sources: [VidurQuickSource] = []
        var speakers: [String] = []
        for hit in shown {
            let doc = hit.doc
            sources.append(context.source(doc.record, label: doc.label, timestamp: doc.timestamp, quote: doc.quote,
                                          speaker: doc.speaker))
            if let name = context.displayName(doc.speaker), name != "Someone", !name.hasPrefix("Speaker "),
               !speakers.contains(name), speakers.count < 3 {
                speakers.append(name)
            }
        }
        // A request found in the transcript ("Pawan asked Neha to send it") is a deterministic owner answer, the same
        // kind as a saved action, so it is complete and no model has to read it again.
        if answersOwner {
            return VidurSection(text: text, sources: sources, people: speakers, isComplete: true, intent: .tasks)
        }
        let complete = top.coverage >= 1.0 && !original.wantsReasoning && isSaved
        return VidurSection(text: text, sources: sources, people: speakers, isComplete: complete, intent: .topic)
    }

    /// "Who owns X?" with no saved action: the person a speaker asked to do it, from the transcript.
    private static func ownerSentence(hits: [Hit], context: VidurQuickContext, keys: Set<String>,
                                      topic: String) -> (text: String, hit: Hit)? {
        for hit in hits.prefix(8) where hit.doc.label == nil {
            guard let found = VidurGist.request(in: hit.doc.text, topicKeys: keys, speaker: hit.doc.speaker,
                                                index: context.index) else { continue }
            let day = context.day(hit.doc.record.date)
            let who = context.speakerWord(hit.doc.speaker)
            let text = "No saved action covers \(topic), but on \(day) \(who) asked \(found.person.canonical) to \(found.phrase)."
            return (text, hit)
        }
        return nil
    }

    /// "What did Pawan say?" without a topic: his longest recent turns.
    private static func personDigest(_ context: VidurQuickContext) -> VidurSection? {
        let people = context.parsed.people
        var picks: [(record: VidurMeetingRecord, turn: VidurMeetingTurn)] = []
        for record in context.records.reversed() {
            let mine = record.turns.filter { turn in
                turn.text.count >= 25 && people.contains { context.index.matches(turn.speaker, $0) }
            }
            for turn in mine.sorted(by: { $0.text.count > $1.text.count }).prefix(3) where picks.count < 3 {
                picks.append((record, turn))
            }
            if !picks.isEmpty { break }
        }
        guard !picks.isEmpty else { return nil }
        let name = people.map(\.canonical).joined(separator: " and ")
        let names = context.firstNames
        var sentences: [String] = []
        var lines: [String] = []
        var sources: [VidurQuickSource] = []
        for pick in picks.sorted(by: { $0.turn.start < $1.turn.start }) {
            let quote = VidurQuickContext.excerpt(pick.turn.text, keys: [], limit: 200)
            lines.append("\u{2022} \(VidurQuickContext.timecode(pick.turn.start)): \u{201C}\(quote)\u{201D}")
            if let clause = VidurGist.clause(from: pick.turn.text, topicKeys: [], names: names) {
                sentences.append("On \(context.day(pick.record.date)), \(name) said that \(clause).")
            }
            sources.append(context.source(pick.record, label: nil, timestamp: pick.turn.start, quote: pick.turn.text,
                                          speaker: pick.turn.speaker))
        }
        if sentences.count == picks.count {
            let body = sentences.count == 1
                ? sentences[0]
                : "Here\u{2019}s what \(name) said:\n" + sentences.map { "\u{2022} " + $0 }.joined(separator: "\n")
            return VidurSection(text: body, sources: sources, people: people.map(\.canonical), isComplete: false,
                                intent: .topic)
        }
        let place = picks[0].record
        return VidurSection(text: "In \(context.label(place)), \(name) said:\n" + lines.joined(separator: "\n"),
                            sources: sources, people: people.map(\.canonical), isComplete: false, intent: .topic)
    }
}
