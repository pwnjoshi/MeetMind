import Foundation
import NaturalLanguage

public final class NaturalLanguageSummarizationService: SummarizationServiceProtocol, @unchecked Sendable {
    private let stopWords: Set<String> = [
        "a", "about", "above", "after", "again", "against", "all", "am", "an", "and", "any", "are",
        "as", "at", "be", "because", "been", "before", "being", "below", "between", "both", "but",
        "by", "could", "did", "do", "does", "doing", "down", "during", "each", "few", "for", "from",
        "further", "had", "has", "have", "having", "he", "her", "here", "hers", "herself", "him",
        "himself", "his", "how", "i", "if", "in", "into", "is", "it", "its", "itself", "just",
        "me", "more", "most", "my", "myself", "no", "nor", "not", "now", "of", "off", "on", "once",
        "only", "or", "other", "ought", "our", "ours", "ourselves", "out", "over", "own", "same",
        "she", "should", "so", "some", "such", "than", "that", "the", "their", "theirs", "them",
        "themselves", "then", "there", "these", "they", "this", "those", "through", "to", "too",
        "under", "until", "up", "very", "was", "we", "were", "what", "when", "where", "which",
        "while", "who", "whom", "why", "with", "would", "you", "your", "yours", "yourself", "yourselves"
    ]
    
    // Compiled word-boundary action item regex pattern eliminating false positives (e.g. William, mustard, shoulder)
    private static let actionItemPattern = #"\b(?:will|must|should|action item|follow up with|follow up|assign to|assigned to|shall|need to|needs to|task)\b"#
    
    public init() {}
    
    public func generateSummary(from transcriptText: String) async throws -> MeetingSummaryResponse {
        let trimmed = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SummarizationError.emptyTranscript
        }
        
        // 1. Sentence Tokenization
        var sentences: [String] = []
        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = trimmed
        sentenceTokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let sentence = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        
        if sentences.isEmpty {
            sentences = [trimmed]
        }
        
        // 2. Word Frequency / TF Analysis
        var wordFrequencies: [String: Int] = [:]
        let wordTokenizer = NLTokenizer(unit: .word)
        wordTokenizer.string = trimmed
        wordTokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let word = String(trimmed[range]).lowercased()
            if !stopWords.contains(word) && word.count > 2 {
                wordFrequencies[word, default: 0] += 1
            }
            return true
        }
        
        // 3. Extractive Sentence Ranking
        var rankedSentences: [(sentence: String, score: Float, index: Int)] = []
        for (index, sentence) in sentences.enumerated() {
            var score: Float = 0.0
            var wordCount = 0
            let sTokenizer = NLTokenizer(unit: .word)
            sTokenizer.string = sentence
            sTokenizer.enumerateTokens(in: sentence.startIndex..<sentence.endIndex) { range, _ in
                let word = String(sentence[range]).lowercased()
                if let freq = wordFrequencies[word] {
                    score += Float(freq)
                }
                wordCount += 1
                return true
            }
            let normalizedScore = wordCount > 0 ? (score / Float(wordCount)) : 0.0
            rankedSentences.append((sentence: sentence, score: normalizedScore, index: index))
        }
        
        // Select top 3-4 sentences in original chronological order for Executive Summary
        let summaryCount = min(4, max(1, sentences.count / 3))
        let topScored = rankedSentences
            .sorted { $0.score > $1.score }
            .prefix(summaryCount)
            .sorted { $0.index < $1.index }
        let executiveSummary = topScored.map { $0.sentence }.joined(separator: " ")
        
        // 4. Key Decisions Extraction
        let decisionKeywords = ["decided", "agreed", "approved", "concluded", "resolution", "finalized", "consensus", "we will proceed with"]
        var keyDecisions: [String] = []
        for sentence in sentences {
            let lower = sentence.lowercased()
            if decisionKeywords.contains(where: { lower.contains($0) }) {
                keyDecisions.append(sentence)
            }
        }
        if keyDecisions.isEmpty && !sentences.isEmpty {
            keyDecisions.append("Key consensus reached during general discussion.")
        }
        
        // 5. Action Items Rule-based Parsing with word-boundary regex
        var actionItems: [ParsedActionItem] = []
        for sentence in sentences {
            if sentence.range(of: Self.actionItemPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                let parsed = parseActionItem(from: sentence)
                actionItems.append(parsed)
            }
        }
        
        // 6. Topics Extraction
        let topTopics = wordFrequencies
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key.capitalized }
        
        let keyDiscussionPoints = topScored.map { $0.sentence }
        
        return MeetingSummaryResponse(
            executiveSummary: executiveSummary,
            keyDiscussionPoints: keyDiscussionPoints,
            keyDecisions: keyDecisions,
            actionItems: actionItems,
            topics: Array(topTopics)
        )
    }
    
    private func parseActionItem(from sentence: String) -> ParsedActionItem {
        // Detect priority
        let lower = sentence.lowercased()
        let priority: String
        if lower.contains("urgent") || lower.contains("asap") || lower.contains("critical") {
            priority = "urgent"
        } else if lower.contains("high priority") || lower.contains("important") {
            priority = "high"
        } else if lower.contains("low priority") || lower.contains("when time permits") {
            priority = "low"
        } else {
            priority = "medium"
        }
        
        // Detect Assignee using robust whitespace regex tokenization (\s+)
        var assignee: String? = nil
        let words: [String]
        if let regex = try? NSRegularExpression(pattern: #"\S+"#) {
            let nsString = sentence as NSString
            let matches = regex.matches(in: sentence, options: [], range: NSRange(location: 0, length: sentence.utf16.count))
            words = matches.map { nsString.substring(with: $0.range) }
        } else {
            words = sentence.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        }
        
        if let willIndex = words.firstIndex(where: {
            let token = $0.lowercased()
            return token == "will" || token == "must" || token == "shall" || token == "should"
        }), willIndex > 0 {
            let candidate = words[willIndex - 1].trimmingCharacters(in: .punctuationCharacters)
            if candidate.first?.isUppercase == true && !["It", "We", "They", "This", "That", "The", "There"].contains(candidate) {
                assignee = candidate
            }
        }
        
        // Detect Due Date using NSDataDetector
        var detectedDate: Date? = nil
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let matches = detector.matches(in: sentence, options: [], range: NSRange(location: 0, length: sentence.utf16.count))
            if let firstMatch = matches.first, let date = firstMatch.date {
                detectedDate = date
            }
        }
        
        return ParsedActionItem(
            title: sentence,
            taskDescription: sentence,
            assignee: assignee,
            dueDate: detectedDate,
            priority: priority
        )
    }
}
