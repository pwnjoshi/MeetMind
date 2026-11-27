import Foundation

/// What the answer engine needs from a loaded language model to write a retrieval answer.
/// `LocalLanguageModel` implements it. Tests provide a fake, so no model is needed.
protocol VidurRagSession {
    /// Number of model tokens in a finished prompt.
    func promptTokenCount(_ prompt: String) throws -> Int
    /// Reads the prompt and writes {"answer":"...","citations":["c1"],"found":true}. `onText` receives the
    /// whole output so far after every token.
    func generateRag(prompt: String, maxTokens: Int, onText: ((String) -> Void)?) throws -> VidurModelAnswer
}
