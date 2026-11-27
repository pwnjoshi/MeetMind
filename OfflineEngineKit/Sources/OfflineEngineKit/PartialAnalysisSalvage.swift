import Foundation

/// Recovers the complete items from model output that stopped at its token limit.
///
/// The analysis grammar writes `{"discussion":[...],"decisions":[...],"tasks":[...]}` and every item
/// ends with its evidence, so an item whose closing brace was written is complete. Cutting right after
/// the last such brace and closing the open brackets gives valid JSON with only finished items.
/// Missing sections become empty lists. The caller still sanitizes the result against the transcript.
enum PartialAnalysisSalvage {
    static func salvage(_ data: Data) -> LocalAnalysisResult? {
        let bytes = [UInt8](data)
        var stack: [UInt8] = []
        var inString = false
        var escaped = false
        // Cut positions (exclusive end index) with the bracket stack still open at that point.
        var cuts: [(end: Int, open: [UInt8])] = []
        for (index, byte) in bytes.enumerated() {
            if inString {
                if escaped { escaped = false }
                else if byte == UInt8(ascii: "\\") { escaped = true }
                else if byte == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""):
                inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                stack.append(byte)
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                guard !stack.isEmpty else { return nil }
                stack.removeLast()
                // A closed object directly inside an array is a finished list item.
                if byte == UInt8(ascii: "}"), stack.last == UInt8(ascii: "[") {
                    cuts.append((index + 1, stack))
                }
            default:
                break
            }
        }
        for cut in cuts.reversed() {
            var candidate = Array(bytes[..<cut.end])
            for bracket in cut.open.reversed() {
                candidate.append(bracket == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]"))
            }
            guard var object = (try? JSONSerialization.jsonObject(with: Data(candidate))) as? [String: Any] else {
                continue
            }
            for key in ["discussion", "decisions", "tasks"] where object[key] == nil { object[key] = [Any]() }
            guard let repaired = try? JSONSerialization.data(withJSONObject: object),
                  let result = try? JSONDecoder().decode(LocalAnalysisResult.self, from: repaired) else { continue }
            return result
        }
        return nil
    }
}
