import Foundation

public final class LLMSummarizationService: SummarizationServiceProtocol, @unchecked Sendable {
    private let endpointURL: URL
    private let apiKey: String
    private let modelName: String
    private let fallbackService: NaturalLanguageSummarizationService
    
    public init(
        endpointURL: URL? = nil,
        apiKey: String = "",
        modelName: String = "gpt-4o-mini"
    ) {
        self.endpointURL = endpointURL ?? (URL(string: "https://api.openai.com/v1/chat/completions") ?? URL(fileURLWithPath: "/"))
        self.apiKey = apiKey
        self.modelName = modelName
        self.fallbackService = NaturalLanguageSummarizationService()
    }
    
    public func generateSummary(from transcriptText: String) async throws -> MeetingSummaryResponse {
        let trimmed = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SummarizationError.emptyTranscript
        }
        
        // Fallback directly if no API key is supplied
        guard !apiKey.isEmpty else {
            return try await fallbackService.generateSummary(from: trimmed)
        }
        
        let systemPrompt = """
        You are MeetMind's meeting intelligence summarizer. Given the transcript, produce a JSON object strictly conforming to:
        {
          "executiveSummary": "Concise 2-4 sentence executive overview.",
          "keyDiscussionPoints": ["Discussion point 1", "Discussion point 2"],
          "keyDecisions": ["Decision 1", "Decision 2"],
          "actionItems": [
            {
              "title": "Short task title",
              "taskDescription": "Details of the action item",
              "assignee": "Name or null",
              "dueDate": "ISO8601 date string or null",
              "priority": "low | medium | high | urgent"
            }
          ],
          "topics": ["Topic 1", "Topic 2"]
        }
        Respond with raw JSON only. Do not wrap in markdown code blocks.
        """
        
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": trimmed]
            ],
            "temperature": 0.2
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            return try await fallbackService.generateSummary(from: trimmed)
        }
        
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 30.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return try await fallbackService.generateSummary(from: trimmed)
            }
            
            // Extract content from LLM response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let contentString = message["content"] as? String {
                
                let cleanedJSONString = Self.stripMarkdownCodeFences(contentString)
                if let contentData = cleanedJSONString.data(using: .utf8) {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    if let summaryResponse = try? decoder.decode(MeetingSummaryResponse.self, from: contentData) {
                        return summaryResponse
                    }
                }
            }
            
            return try await fallbackService.generateSummary(from: trimmed)
        } catch {
            return try await fallbackService.generateSummary(from: trimmed)
        }
    }
    
    /// Strips markdown code fences (e.g. ```json ... ```) to prevent decoding failures
    public static func stripMarkdownCodeFences(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            if let firstLineBreak = trimmed.firstIndex(where: { $0.isNewline }) {
                trimmed = String(trimmed[trimmed.index(after: firstLineBreak)...])
            } else {
                trimmed = trimmed.replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
            }
        }
        if trimmed.hasSuffix("```") {
            trimmed = String(trimmed.dropLast(3))
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
