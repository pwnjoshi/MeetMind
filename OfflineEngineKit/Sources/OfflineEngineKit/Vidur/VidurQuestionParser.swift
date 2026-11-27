import Foundation

public enum VidurQuickTaskFilter: Sendable, Equatable { case all, open, done, due, overdue }

/// What a question asks for. Built without a model from English, Hinglish and Devanagari words.
struct VidurParsedQuestion {
    var intents: [VidurQuickIntent] = []
    var people: [VidurPerson] = []
    var asksForSelf = false
    var taskFilter: VidurQuickTaskFilter = .all
    /// Tasks must be due inside this range ("due this week").
    var dueRange: DateInterval?
    /// Meetings must fall inside this range ("last week").
    var meetingRange: DateInterval?
    var rangeLabel: String?
    var lastMeeting = false
    /// Topic words the intent keywords do not explain ("pricing" in "what did we decide about pricing").
    var residual: [String] = []
    var wantsCount = false
    var whoSaid = false
    /// "who owns the presentation", "who is responsible for it": the answer is a person.
    var asksOwner = false
    var wantsReasoning = false
    /// "and", "also", "what about" or a pronoun: the question leans on the one before it.
    var followUpCue = false
    /// "it", "that", "his", "uska": the question refers back to something.
    var pronounCue = false
    var wordCount = 0
    /// Titles of saved meetings the question names ("the Weekly sync"). The answer is limited to them.
    var matchedTitles: [String] = []
}

enum VidurQuestionParser {
    // MARK: Vocabulary

    static let taskWords: Set<String> = [
        "task", "tasks", "action", "actions", "todo", "todos", "assigned", "assign", "assignee", "owner", "owners",
        "responsible", "deliverable", "deliverables", "followup", "followups", "kaam", "kaams", "zimmedari",
        "jimmedari", "zimmedaari", "commit", "committed", "commitment", "commitments", "promise", "promised",
        "promises", "owe", "owes", "owed", "owns", "handle", "handling", "karega", "karegi", "karenge", "lega",
        "legi", "dega", "degi", "काम", "कार्य", "जिम्मेदारी"
    ]
    static let dueWords: Set<String> = ["due", "deadline", "deadlines", "overdue", "samay", "tarikh", "तारीख"]
    static let agreeWords: Set<String> = ["agree", "agreed", "agreement", "agreements", "sahmat", "manzoor"]
    static let decisionWords: Set<String> = [
        "decide", "decided", "decision", "decisions", "finalize", "finalized", "finalised", "finalise", "conclude",
        "concluded", "resolution", "resolutions", "approved", "approve", "faisla", "faisle", "nirnay", "tay", "tai",
        "फैसला", "फैसले", "निर्णय", "तय"
    ]
    static let issueWords: Set<String> = [
        "unresolved", "issue", "issues", "undecided", "unclear", "unanswered", "concern", "concerns", "risk",
        "risks", "blocker", "blockers", "blocked", "problem", "problems", "samasya", "dikkat", "समस्या"
    ]
    static let attendeeWords: Set<String> = [
        "attendees", "attendee", "attended", "attendance", "participants", "participant", "present", "joined",
        "hazir", "haazir", "upasthit", "aaya", "aaye", "aayi", "उपस्थित"
    ]
    static let absentWords: Set<String> = ["absent", "absentee", "absentees", "anupasthit", "missing", "अनुपस्थित"]
    static let agendaWords: Set<String> = ["agenda", "agendas", "एजेंडा"]
    static let summaryWords: Set<String> = [
        "summary", "summarize", "summarise", "recap", "overview", "tldr", "gist", "saransh", "highlights", "सारांश"
    ]
    static let durationWords: Set<String> = ["duration"]
    static let dateWords: Set<String> = ["date", "tarikh", "when"]
    static let openWords: Set<String> = ["open", "pending", "remaining", "incomplete", "outstanding", "unfinished", "baaki", "left"]
    static let doneWords: Set<String> = ["done", "completed", "finished", "closed", "complete"]
    static let personTaskVerbs: Set<String> = [
        "agree", "agreed", "commit", "committed", "promise", "promised", "handle", "own", "owns", "doing",
        "responsible", "deliver", "karega", "karegi", "karenge", "lega", "legi", "dega", "degi", "assigned",
        "owe", "owes"
    ]
    static let speechVerbs: Set<String> = [
        "say", "said", "says", "mention", "mentioned", "raised", "raise", "suggest", "suggested", "proposed",
        "propose", "told", "tell", "bola", "kaha", "bole", "boli", "bataya", "spoke", "speak", "talk", "talked"
    ]
    static let selfWords: Set<String> = ["my", "mine", "mujhe", "mera", "meri", "mere", "myself"]
    static let reasoningWords: Set<String> = ["why", "explain", "reason", "kyun", "kyu", "compare", "difference", "justify"]
    static let timeWords: Set<String> = [
        "today", "yesterday", "tomorrow", "kal", "week", "weeks", "month", "months", "aaj", "hafte", "hafta", "mahine",
        "last", "this", "next", "previous", "latest", "recent", "recently", "pichhle", "pichle", "pichli", "pichhli",
        "akhri", "aakhri", "ago", "past", "days", "day", "din", "tak", "monday", "tuesday", "wednesday", "thursday",
        "friday", "saturday", "sunday", "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december"
    ]
    static let genericWords: Set<String> = [
        "meeting", "meetings", "call", "calls", "session", "discussed", "discuss", "discussion", "everyone", "anyone",
        "someone", "people", "person", "please", "show", "list", "give", "still", "steps", "step", "everything",
        "item", "items", "point", "points", "whats", "mujhe", "batao", "bataiye", "dikhao", "sab", "sabhi", "who",
        "whom", "kaun", "kaunsa", "kaunse", "first", "total", "long", "kitni", "der", "kitna", "kitne", "time",
        "lamba", "happened", "hua", "hui", "baat", "key", "main", "sum", "there", "came", "attend", "join", "missed",
        "baare", "baarein", "bare", "going", "working", "taking", "follow", "gair", "nahi", "hazir", "gaya", "chuka", "karna", "date",
        "regarding", "related", "concerning", "name", "names", "need", "needs", "needed", "many", "much", "number",
        "count", "how", "what", "which", "kya", "kuch", "koi", "also", "already", "yet", "about", "after", "before",
        "between", "during", "where", "with", "from", "again", "been", "being", "have", "has", "had", "does", "did",
        "will", "shall", "would", "should", "could", "can", "may", "might", "must", "want", "wants", "like", "tell",
        "make", "made", "work", "raised", "kab", "kaise", "kyun", "kyu", "aur", "bhi", "know", "found", "get", "got",
        "all", "any", "our", "your", "their", "his", "her", "its", "them", "they", "she", "was", "were", "are", "the",
        "and", "for", "you", "that", "this", "those", "these", "than", "then", "when", "whose", "into", "onto"
    ]

    static let vocabulary: Set<String> = {
        var all = Set<String>()
        let sets: [Set<String>] = [
            VidurQuestionParser.taskWords, VidurQuestionParser.dueWords, VidurQuestionParser.agreeWords,
            VidurQuestionParser.decisionWords, VidurQuestionParser.issueWords, VidurQuestionParser.attendeeWords,
            VidurQuestionParser.absentWords, VidurQuestionParser.agendaWords, VidurQuestionParser.summaryWords,
            VidurQuestionParser.durationWords, VidurQuestionParser.dateWords, VidurQuestionParser.openWords,
            VidurQuestionParser.doneWords, VidurQuestionParser.personTaskVerbs, VidurQuestionParser.speechVerbs,
            VidurQuestionParser.selfWords, VidurQuestionParser.reasoningWords, VidurQuestionParser.timeWords,
            VidurQuestionParser.genericWords
        ]
        for set in sets {
            all.formUnion(set)
        }
        return all
    }()

    // MARK: Parsing

    static func parse(_ rawQuestion: String, index: VidurPersonIndex, titles: [String] = [], now: Date,
                      calendar: Calendar) -> VidurParsedQuestion {
        let question = (rawQuestion.lowercased() + " ")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "'s ", with: " ")
            .replacingOccurrences(of: "'", with: "")
        let words = question.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let wordSet = Set(words)
        let padded = " " + words.joined(separator: " ") + " "
        func has(_ set: Set<String>) -> Bool { !wordSet.isDisjoint(with: set) }
        func phrase(_ list: [String]) -> Bool { list.contains { padded.contains(" \($0) ") } }

        var parsed = VidurParsedQuestion()
        parsed.wordCount = words.count

        // People
        var nameWords = Set<String>()
        for word in words where word.count >= 2 && !vocabulary.contains(word) && !VidurTokenizer.stopWords.contains(word) {
            if let person = index.person(forWord: word) {
                if !parsed.people.contains(person) { parsed.people.append(person) }
                nameWords.insert(word)
            }
        }
        parsed.asksForSelf = has(selfWords)
            || phrase(["owe me", "assigned to me", "for me", "i need", "do i", "should i", "i have", "mere liye", "i am", "im"])

        // Meeting titles named in the question
        var titleWords = Set<String>()
        for title in titles {
            let terms = VidurScript.words(title).filter {
                $0.count > 2 && !VidurTokenizer.stopWords.contains($0) && !vocabulary.contains($0)
            }
            guard !terms.isEmpty else { continue }
            var matched = Set<String>()
            var every = true
            for term in terms {
                let termKeys = Set(VidurScript.keys(forWord: term))
                if let hit = words.first(where: { !termKeys.isDisjoint(with: VidurScript.keys(forWord: $0)) }) {
                    matched.insert(hit)
                } else {
                    every = false
                    break
                }
            }
            if every {
                parsed.matchedTitles.append(title)
                titleWords.formUnion(matched)
            }
        }

        // Time
        let scope = timeScope(padded: padded, now: now, calendar: calendar)
        parsed.lastMeeting = phrase([
            "last meeting", "latest meeting", "previous meeting", "recent meeting", "most recent meeting", "last call",
            "previous call", "pichli meeting", "pichhli meeting", "pichhle meeting", "pichle meeting", "aakhri meeting",
            "akhri meeting", "last time", "meeting before this"
        ])

        // Task and filter cues
        let hasDueWord = has(dueWords) || phrase(["kab tak", "by when", "by"])
        var isTask = has(taskWords) || has(dueWords)
            || phrase(["follow up", "to do", "kya karna", "kya karna hai", "kab tak", "by when", "who will",
                       "who is going to", "who should", "kisko kya", "what do i need", "what should i do",
                       "who has to", "who have to", "who needs to", "who need to", "who is in charge", "who responsible"])
        if !parsed.people.isEmpty, has(personTaskVerbs) || phrase(["working on", "taking on", "karna hai", "kya karega", "kya karegi"]) {
            isTask = true
        }
        let agreeOnly = has(agreeWords) && !isTask

        if wordSet.contains("overdue") { parsed.taskFilter = .overdue }
        else if phrase(["not completed", "not done", "not finished", "not complete", "nahi hua", "nahi hui"]) { parsed.taskFilter = .open }
        else if has(doneWords) || phrase(["ho gaya", "ho chuka", "complete ho"]) { parsed.taskFilter = .done }
        else if has(openWords) { parsed.taskFilter = .open }
        else if has(dueWords) || phrase(["kab tak", "by when"]) { parsed.taskFilter = .due }

        if let scope {
            if scope.forward || (isTask && hasDueWord) {
                parsed.dueRange = scope.range
                if parsed.taskFilter == .all { parsed.taskFilter = .due }
            } else {
                parsed.meetingRange = scope.range
            }
            parsed.rangeLabel = scope.label
        }

        // Intents
        let notPresent = phrase(["not present", "gair hazir"])
        let absentAsked = has(absentWords) || notPresent
            || phrase(["didnt attend", "did not attend", "didnt join", "did not join", "nahi aaya", "nahi aaye", "nahi aayi", "who missed"])
        let attendeesAsked = has(attendeeWords.subtracting(["present"])) || (wordSet.contains("present") && !notPresent)
            || phrase(["who was there", "who all", "who came", "who joined", "kaun kaun", "kaun aaya", "kaun tha", "kaun the",
                       "who were", "who was in", "who is in", "was there", "were there", "at the meeting"])
        let nextMeeting = phrase(["next meeting", "next call", "agli meeting", "agle meeting", "agla meeting", "meet again",
                                  "next session", "follow up meeting", "followup meeting", "reconvene", "agli baar"])
        let openIssuePhrase = has(openWords) && has(["question", "questions", "issue", "issues", "points", "topics"]) && !isTask
        let summaryAsked = has(summaryWords)
            || phrase(["what happened", "kya hua", "what was discussed", "what did we discuss", "what we discussed",
                       "kya discuss hua", "key points", "main points", "kya baat hui", "sum up",
                       "meeting about", "was it about", "was discussed"])
        let durationAsked = has(durationWords) || phrase(["how long", "kitni der", "kitna time", "kitne der", "kitna lamba"])
        let dateAsked = phrase(["what date", "which date", "when was", "when did the meeting", "kab hui", "kab hua", "what day",
                                "kis din", "kis date"])
            || (has(dateWords) && !isTask && wordSet.contains("meeting"))
        parsed.wantsCount = phrase(["how many", "kitne", "kitni", "count", "number of", "total"])
        parsed.whoSaid = has(["who", "kaun", "kisne"]) && has(speechVerbs) || phrase(["kisne kaha", "kisne bola", "who said"])
        parsed.asksOwner = phrase([
            "who owns", "who own", "who is responsible", "who is handling", "who handles", "who is taking care",
            "who has to", "who have to", "who needs to", "who need to", "who will", "who is going to", "who should",
            "whose task", "whose job", "whose responsibility", "whose action", "who owned", "who responsible",
            "who is in charge", "who is incharge", "who is accountable",
            "kaun karega", "kaun karegi", "kiski zimmedari", "kiski jimmedari"
        ])
        parsed.wantsReasoning = has(reasoningWords) || phrase(["how come", "how did", "how do", "how can", "how should"])
        parsed.pronounCue = phrase(["uska", "uski", "unka", "his", "her", "their", "isme", "usme", "it", "that", "those", "its"])
        parsed.followUpCue = parsed.pronounCue || phrase(["and", "aur", "also", "what about", "how about"])

        var intents: [VidurQuickIntent] = []
        if nextMeeting {
            intents.append(.nextMeeting)
        } else {
            if isTask { intents.append(.tasks) }
            if has(decisionWords) || (agreeOnly && parsed.people.isEmpty) { intents.append(.decisions) }
            if has(issueWords) || openIssuePhrase { intents.append(.openIssues) }
            if absentAsked { intents.append(.absent) }
            if attendeesAsked { intents.append(.attendees) }
            if has(agendaWords) { intents.append(.agenda) }
            if summaryAsked { intents.append(.summary) }
            if durationAsked { intents.append(.duration) }
            if dateAsked { intents.append(.date) }
            // "pending" alone means open tasks.
            if intents.isEmpty, has(openWords), !wordSet.contains("question"), !wordSet.contains("questions") {
                intents.append(.tasks)
                if parsed.taskFilter == .all { parsed.taskFilter = .open }
            }
            if intents.isEmpty, wordSet.contains("meetings") || phrase(["which meetings", "kitni meetings", "kitne meetings"]),
               parsed.wantsCount || parsed.meetingRange != nil || phrase(["which meetings", "list meetings", "show meetings"]) {
                intents.append(.meetingList)
            }
        }
        parsed.intents = intents

        // Residual topic words
        parsed.residual = words.filter { word in
            word.count > 2 && !VidurTokenizer.stopWords.contains(word) && !vocabulary.contains(word)
                && !nameWords.contains(word) && !titleWords.contains(word) && !word.allSatisfy(\.isNumber)
        }

        // A meeting question with no other intent ("what was the last meeting about?") is a summary.
        if parsed.intents.isEmpty, parsed.lastMeeting, parsed.residual.isEmpty, parsed.people.isEmpty {
            parsed.intents = [.summary]
        }
        // Topic words turn a general question into a search.
        let topical: Set<VidurQuickIntent> = [.summary, .attendees, .absent, .agenda, .duration, .date, .meetingList]
        if !parsed.residual.isEmpty, !parsed.intents.isEmpty, parsed.intents.allSatisfy({ topical.contains($0) }) {
            parsed.intents = [.topic]
        }
        if parsed.intents.isEmpty { parsed.intents = [.topic] }
        if parsed.intents == [.topic], parsed.residual.isEmpty, parsed.people.isEmpty, !parsed.matchedTitles.isEmpty {
            parsed.intents = [.summary]
        }
        return parsed
    }

    // MARK: Time scope

    struct TimeScope {
        let range: DateInterval
        let label: String
        /// True for words that only make sense for something due later ("tomorrow", "next week").
        let forward: Bool
    }

    static func timeScope(padded: String, now: Date, calendar: Calendar) -> TimeScope? {
        func phrase(_ list: [String]) -> Bool { list.contains { padded.contains(" \($0) ") } }
        let startOfDay = calendar.startOfDay(for: now)
        func interval(_ start: Date?, _ end: Date?) -> DateInterval? {
            guard let start, let end, end >= start else { return nil }
            return DateInterval(start: start, end: end)
        }
        func week(offset: Int) -> DateInterval? {
            guard let current = calendar.dateInterval(of: .weekOfYear, for: now),
                  let start = calendar.date(byAdding: .weekOfYear, value: offset, to: current.start),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            return interval(start, end)
        }
        func month(offset: Int) -> DateInterval? {
            guard let current = calendar.dateInterval(of: .month, for: now),
                  let start = calendar.date(byAdding: .month, value: offset, to: current.start),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            return interval(start, end)
        }

        if phrase(["last week", "previous week", "pichhle hafte", "pichle hafte", "pichhle hafta", "pichle hafta"]),
           let range = week(offset: -1) { return TimeScope(range: range, label: "last week", forward: false) }
        if phrase(["next week", "agle hafte", "agli week"]), let range = week(offset: 1) {
            return TimeScope(range: range, label: "next week", forward: true)
        }
        if phrase(["this week", "is hafte", "iss hafte", "is week", "iss week", "this weeks"]), let range = week(offset: 0) {
            return TimeScope(range: range, label: "this week", forward: false)
        }
        if phrase(["last month", "previous month", "pichhle mahine", "pichle mahine"]), let range = month(offset: -1) {
            return TimeScope(range: range, label: "last month", forward: false)
        }
        if phrase(["this month", "is mahine", "iss mahine"]), let range = month(offset: 0) {
            return TimeScope(range: range, label: "this month", forward: false)
        }
        if phrase(["past week", "last 7 days", "past 7 days", "last seven days"]),
           let start = calendar.date(byAdding: .day, value: -7, to: now), let range = interval(start, now) {
            return TimeScope(range: range, label: "in the past 7 days", forward: false)
        }
        if phrase(["yesterday"]), let start = calendar.date(byAdding: .day, value: -1, to: startOfDay),
           let range = interval(start, startOfDay) {
            return TimeScope(range: range, label: "yesterday", forward: false)
        }
        if phrase(["tomorrow", "kal tak"]), let start = calendar.date(byAdding: .day, value: 1, to: startOfDay),
           let end = calendar.date(byAdding: .day, value: 2, to: startOfDay), let range = interval(start, end) {
            return TimeScope(range: range, label: "tomorrow", forward: true)
        }
        if phrase(["today", "aaj"]), let end = calendar.date(byAdding: .day, value: 1, to: startOfDay),
           let range = interval(startOfDay, end) {
            return TimeScope(range: range, label: "today", forward: false)
        }
        return nil
    }
}
