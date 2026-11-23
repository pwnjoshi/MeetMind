import Foundation
import OfflineEngineKit

/// Runs the production analysis pipeline over golden-set recordings pushed to
/// `Documents/Evaluation/<id>/` and writes `result.json` next to each recording.
///
/// Isolation: this uses no SwiftData store at all and its own checkpoint folder inside
/// `tmp/`, so a user's meetings, recordings and checkpoints are never read or changed.
/// Console lines carry the MEETMIND_EVAL prefix and contain no transcript text.
@MainActor
enum EvaluationRunner {
    struct Options {
        /// Only these folder names, from `--eval-only=a,b`. Nil means every folder.
        var only: Set<String>?
        /// Forced Whisper language code from `--eval-language=hi`. Nil means automatic.
        var language: String?
    }

    struct LabelContext {
        var participants: [String] = []
        var agenda: String?
    }

    static let audioExtensions = ["m4a", "wav", "caf", "mp3", "aac", "mp4"]

    static func line(_ text: String) {
        print("MEETMIND_EVAL " + text)
        fflush(stdout)
    }

    static func options(from arguments: [String]) -> Options {
        var options = Options()
        for argument in arguments {
            if argument.hasPrefix("--eval-only=") {
                let names = argument.dropFirst("--eval-only=".count)
                    .split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                options.only = Set(names)
            } else if argument.hasPrefix("--eval-language=") {
                let code = String(argument.dropFirst("--eval-language=".count))
                    .trimmingCharacters(in: .whitespaces)
                options.language = code.isEmpty ? nil : code
            }
        }
        return options
    }

    static func evaluationRoot() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Evaluation", isDirectory: true)
    }

    static func audioFile(in folder: URL) -> URL? {
        for ext in audioExtensions {
            let candidate = folder.appendingPathComponent("audio." + ext)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Reads attendee names and agenda points from labels.json when it exists. Missing or
    /// malformed labels simply mean no participants and no agenda.
    static func labelContext(in folder: URL) -> LabelContext {
        var context = LabelContext()
        let url = folder.appendingPathComponent("labels.json")
        guard let data = try? Data(contentsOf: url),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return context }
        var names = (object["participants"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if names.isEmpty, let speakers = object["speakers"] as? [[String: Any]] {
            names = speakers.compactMap { ($0["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        context.participants = names
        let points = (object["agenda"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        context.agenda = points.isEmpty ? nil : points.joined(separator: "\n")
        return context
    }

    static func deviceIdentifier() -> String {
        var system = utsname()
        uname(&system)
        return Mirror(reflecting: system.machine).children.reduce("") { text, element in
            guard let value = element.value as? Int8, value != 0 else { return text }
            return text + String(UnicodeScalar(UInt8(bitPattern: value)))
        }
    }

    /// Returns true when every selected recording produced a result.
    static func runAll(options: Options, status: (String) -> Void) async -> Bool {
        let root = evaluationRoot()
        let fileManager = FileManager.default
        let names = ((try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
        let selected = names.filter { name in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.appendingPathComponent(name).path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            return options.only.map { $0.contains(name) } ?? true
        }
        let commit = Bundle.main.object(forInfoDictionaryKey: "ManentBuildCommit") as? String ?? "unknown"
        let device = deviceIdentifier()
        line("start folders=\(selected.count) commit=\(commit) device=\(device)")
        let scratch = fileManager.temporaryDirectory.appendingPathComponent("EvaluationScratch", isDirectory: true)
        try? fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
        var completed = 0
        var failed = 0
        for name in selected {
            if Task.isCancelled { line("cancelled"); return false }
            let folder = root.appendingPathComponent(name, isDirectory: true)
            guard let audio = audioFile(in: folder) else {
                line("skipped id=\(name) reason=no_audio")
                failed += 1
                continue
            }
            status("Evaluating \(name)")
            line("meeting id=\(name) state=running")
            let context = labelContext(in: folder)
            do {
                let result = try await MeetingEvaluation.run(
                    id: name, audio: audio, participants: context.participants, agenda: context.agenda,
                    languageCode: options.language, commit: commit, device: device, scratchRoot: scratch)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(result)
                try data.write(to: folder.appendingPathComponent("result.json"), options: .atomic)
                completed += 1
                let t = result.timings
                line("meeting id=\(name) state=done audio_s=\(Int(result.audioSeconds)) turns=\(result.turns.count) total_ms=\(t.totalMs) transcribe_ms=\(t.transcribeMs) speakers_ms=\(t.speakersMs) minutes_ms=\(t.minutesMs) peak_mb=\(result.peakFootprintMB)")
            } catch is CancellationError {
                line("cancelled")
                try? fileManager.removeItem(at: scratch)
                return false
            } catch {
                failed += 1
                line("meeting id=\(name) state=failed type=\(String(reflecting: type(of: error))) message=\(String(reflecting: error.localizedDescription))")
            }
        }
        try? fileManager.removeItem(at: scratch)
        line("completed ok=\(completed) failed=\(failed)")
        return failed == 0 && completed > 0
    }
}
