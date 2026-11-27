import SwiftUI
import SwiftData
import AVFoundation
import OfflineEngineKit
import OSLog

/// One line of the public scripted Hindi dialogue. `speaker` 0 is Neha, 1 is Pawan.
struct HindiScriptLine {
    let speaker: Int
    let text: String
}

enum HindiScript {
    /// The scripted Neha/Pawan dialogue (public synthetic text, Devanagari with English words).
    static let lines: [HindiScriptLine] = [
        HindiScriptLine(speaker: 0, text: "\u{0939}\u{093E}\u{092F} \u{092A}\u{0935}\u{0928}, \u{091A}\u{0932}\u{094B} \u{0906}\u{091C} \u{0915}\u{0940} \u{092E}\u{0940}\u{091F}\u{093F}\u{0902}\u{0917} \u{0936}\u{0941}\u{0930}\u{0942} \u{0915}\u{0930}\u{0924}\u{0947} \u{0939}\u{0948}\u{0902}\u{0964} \u{0906}\u{091C} \u{0939}\u{092E}\u{0947}\u{0902} launch \u{0914}\u{0930} budget \u{092A}\u{0930} \u{092C}\u{093E}\u{0924} \u{0915}\u{0930}\u{0928}\u{0940} \u{0939}\u{0948}\u{0964}"),
        HindiScriptLine(speaker: 1, text: "\u{0939}\u{093E}\u{0901} \u{0928}\u{0947}\u{0939}\u{093E}, \u{0920}\u{0940}\u{0915} \u{0939}\u{0948}\u{0964} \u{092A}\u{0939}\u{0932}\u{0947} launch date \u{0915}\u{0940} \u{092C}\u{093E}\u{0924} \u{0915}\u{0930} \u{0932}\u{0947}\u{0924}\u{0947} \u{0939}\u{0948}\u{0902}\u{0964}"),
        HindiScriptLine(speaker: 0, text: "\u{092E}\u{0941}\u{091D}\u{0947} \u{0932}\u{0917}\u{0924}\u{093E} \u{0939}\u{0948} \u{0939}\u{092E}\u{0947}\u{0902} 20 November \u{0915}\u{094B} launch \u{0915}\u{0930}\u{0928}\u{093E} \u{091A}\u{093E}\u{0939}\u{093F}\u{090F}\u{0964} \u{0924}\u{0941}\u{092E}\u{094D}\u{0939}\u{0947}\u{0902} \u{0915}\u{094D}\u{092F}\u{093E} \u{0932}\u{0917}\u{0924}\u{093E} \u{0939}\u{0948}?"),
        HindiScriptLine(speaker: 1, text: "\u{0939}\u{093E}\u{0901}, 20 November \u{0938}\u{0939}\u{0940} \u{0930}\u{0939}\u{0947}\u{0917}\u{093E}\u{0964} \u{091A}\u{0932}\u{094B}, launch 20 November \u{0915}\u{094B} \u{0939}\u{0940} final \u{0915}\u{0930}\u{0924}\u{0947} \u{0939}\u{0948}\u{0902}\u{0964}"),
        HindiScriptLine(speaker: 0, text: "\u{0920}\u{0940}\u{0915} \u{0939}\u{0948}, \u{092F}\u{0939} final \u{0939}\u{0948}\u{0964} \u{0905}\u{092C} vendor \u{0915}\u{0947} \u{092C}\u{093E}\u{0930}\u{0947} \u{092E}\u{0947}\u{0902} \u{092C}\u{093E}\u{0924} \u{0915}\u{0930}\u{0924}\u{0947} \u{0939}\u{0948}\u{0902}\u{0964}"),
        HindiScriptLine(speaker: 1, text: "\u{092E}\u{0947}\u{0930}\u{0947} \u{0939}\u{093F}\u{0938}\u{093E}\u{092C} \u{0938}\u{0947} Pune \u{0935}\u{093E}\u{0932}\u{093E} vendor \u{0905}\u{091A}\u{094D}\u{091B}\u{093E} \u{0939}\u{0948}, \u{0909}\u{0938}\u{0915}\u{093E} price \u{092D}\u{0940} \u{0915}\u{092E} \u{0939}\u{0948}\u{0964}"),
        HindiScriptLine(speaker: 0, text: "\u{0939}\u{093E}\u{0901}, let's go with the Pune vendor."),
        HindiScriptLine(speaker: 0, text: "\u{092A}\u{0935}\u{0928}, \u{0915}\u{094D}\u{092F}\u{093E} \u{0924}\u{0941}\u{092E} Friday \u{0924}\u{0915} agenda \u{0924}\u{0948}\u{092F}\u{093E}\u{0930} \u{0915}\u{0930} \u{0938}\u{0915}\u{0924}\u{0947} \u{0939}\u{094B}?"),
        HindiScriptLine(speaker: 1, text: "\u{0939}\u{093E}\u{0901}, \u{091C}\u{093C}\u{0930}\u{0942}\u{0930}\u{0964} \u{092E}\u{0948}\u{0902} Friday \u{0924}\u{0915} agenda \u{092C}\u{0928}\u{093E} \u{0926}\u{0942}\u{0901}\u{0917}\u{093E}\u{0964}"),
        HindiScriptLine(speaker: 1, text: "\u{0914}\u{0930} \u{0928}\u{0947}\u{0939}\u{093E}, \u{0924}\u{0941}\u{092E} \u{0915}\u{0932} \u{0924}\u{0915} client \u{0915}\u{094B} presentation \u{092D}\u{0947}\u{091C} \u{0926}\u{094B}\u{0917}\u{0940}?"),
        HindiScriptLine(speaker: 0, text: "\u{0939}\u{093E}\u{0901}, \u{092E}\u{0948}\u{0902} \u{0915}\u{0932} \u{0924}\u{0915} presentation \u{092D}\u{0947}\u{091C} \u{0926}\u{0942}\u{0901}\u{0917}\u{0940}\u{0964}"),
        HindiScriptLine(speaker: 1, text: "Budget \u{0915}\u{093E} \u{0915}\u{094D}\u{092F}\u{093E} \u{0915}\u{0930}\u{0947}\u{0902}? Marketing \u{0915}\u{0947} \u{0932}\u{093F}\u{090F} \u{0915}\u{093F}\u{0924}\u{0928}\u{093E} \u{0930}\u{0916}\u{0947}\u{0902}?"),
        HindiScriptLine(speaker: 0, text: "Budget \u{0905}\u{092D}\u{0940} decide \u{0928}\u{0939}\u{0940}\u{0902} \u{0939}\u{0941}\u{0906} \u{0939}\u{0948}\u{0964} \u{0909}\u{0938} \u{092A}\u{0930} \u{0905}\u{0917}\u{0932}\u{0940} \u{092E}\u{0940}\u{091F}\u{093F}\u{0902}\u{0917} \u{092E}\u{0947}\u{0902} \u{092C}\u{093E}\u{0924} \u{0915}\u{0930}\u{0947}\u{0902}\u{0917}\u{0947}\u{0964}"),
        HindiScriptLine(speaker: 1, text: "\u{0920}\u{0940}\u{0915} \u{0939}\u{0948}\u{0964} Design change \u{0915}\u{0930}\u{0928}\u{093E} \u{0939}\u{0948} \u{092F}\u{093E} \u{0928}\u{0939}\u{0940}\u{0902}, \u{0935}\u{094B} \u{092D}\u{0940} \u{0905}\u{092D}\u{0940} \u{0924}\u{092F} \u{0928}\u{0939}\u{0940}\u{0902} \u{0939}\u{0941}\u{0906}\u{0964}"),
        HindiScriptLine(speaker: 0, text: "\u{0939}\u{093E}\u{0901}, \u{0935}\u{094B} \u{092D}\u{0940} pending \u{0939}\u{0948}\u{0964} \u{0920}\u{0940}\u{0915} \u{0939}\u{0948}, \u{0906}\u{091C} \u{0915}\u{0947} \u{0932}\u{093F}\u{090F} \u{0907}\u{0924}\u{0928}\u{093E} \u{0939}\u{0940}\u{0964} Thank you \u{092A}\u{0935}\u{0928}\u{0964}")
    ]
}

/// USB-triggered synthetic Hindi end-to-end check (`--offline-hindi-smoke`). It speaks the scripted
/// dialogue with two system hi-IN voices, runs the real production pipeline on that audio in a separate
/// in-memory store, and prints every result with the MEETMIND_HINDI prefix. It never reads or changes
/// a user's meetings, and only public synthetic text is printed.
@MainActor
struct HindiPipelineSmokeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = "Synthetic Hindi pipeline check"
    @State private var operation: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            Text("Synthetic Hindi test").font(.title2)
            Text(status)
            Text("Keep MeetMind open. This speaks a public scripted dialogue with the system Hindi voices and does not change your saved meetings.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { start() }
        .onDisappear { operation?.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { operation?.cancel() }
        }
    }

    private func start() {
        guard operation == nil else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        operation = Task { @MainActor in
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            let id = UUID()
            var audioURL: URL?
            do {
                status = "Speaking the scripted dialogue"
                let url = try await HindiSpeechFixture.render()
                audioURL = url
                let container = try ModelContainerFactory.createInMemoryContainer()
                let context = container.mainContext
                let meeting = Meeting(id: id, title: "Synthetic Hindi pipeline check", status: .processing, audioFileURL: url)
                let neha = Speaker(name: "Neha")
                let pawan = Speaker(name: "Pawan")
                context.insert(meeting)
                context.insert(neha)
                context.insert(pawan)
                meeting.addParticipant(neha)
                meeting.addParticipant(pawan)
                try context.save()
                let vm = ProcessingPipelineViewModel(meeting: meeting, modelContext: context)
                vm.onOfflineStageChanged = { stage in
                    status = "Running: \(stage.rawValue)"
                    print("MEETMIND_HINDI stage \(stage.rawValue)"); fflush(stdout)
                }
                try vm.prepareForProduction(context: context)
                guard try await vm.missingOfflineModels().isEmpty else {
                    throw OfflineError.unavailable("Download the required models in meeting setup first.")
                }
                print("MEETMIND_HINDI running"); fflush(stdout)
                try await vm.startPipeline()
                let passed = HindiSmokeReport.emit(meeting: meeting, pipelineCompleted: vm.pipelineStatus == .completed)
                status = passed ? "PASS" : "FAIL: see the MEETMIND_HINDI output"
                print("MEETMIND_HINDI completed result=\(passed ? "PASS" : "FAIL")"); fflush(stdout)
            } catch is CancellationError {
                status = "Paused. Restart the Hindi check while MeetMind stays open."
                print("MEETMIND_HINDI cancelled"); fflush(stdout)
            } catch {
                status = error.localizedDescription
                if case OfflineError.memoryBudget(let required, let available) = error {
                    print("MEETMIND_HINDI failed memory_required=\(required) memory_available=\(available)")
                } else {
                    print("MEETMIND_HINDI failed type=\(String(reflecting: type(of: error))) message=\(String(reflecting: error.localizedDescription))")
                }
                fflush(stdout)
            }
            if let audioURL = audioURL { try? FileManager.default.removeItem(at: audioURL) }
            try? await MeetingAnalysisPipeline.shared.removeCheckpoint(meetingID: id)
        }
    }
}

/// Prints the transcript and every extracted item, then the PASS/FAIL expectations.
@MainActor
enum HindiSmokeReport {
    private static func line(_ text: String) {
        print("MEETMIND_HINDI " + text)
        // The USB console stream can drop at the end of a long run; the system log keeps the
        // report. It only contains the scripted synthetic dialogue, never a user's meeting.
        Logger(subsystem: "com.meetmind.app", category: "HindiSmoke").notice("MEETMIND_HINDI \(text, privacy: .public)")
    }

    private static func hasDevanagari(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value >= 0x0900 && $0.value <= 0x097F }
    }

    static func emit(meeting: Meeting, pipelineCompleted: Bool) -> Bool {
        let segments = meeting.transcriptSegments.sorted { $0.startTime < $1.startTime }
        let transcript = segments.map(\.text).joined(separator: " ")
        line("transcript_text=\(String(reflecting: transcript))")
        for (index, segment) in segments.enumerated() {
            line("turn index=\(index) text=\(String(reflecting: segment.text))")
        }
        let analysis = meeting.offlineAnalysis
        let results = analysis?.analysis ?? []
        let tasks = results.flatMap(\.tasks)
        let decisions = results.flatMap(\.decisions)
        let openIssues = results.flatMap(\.openIssues)
        for (index, task) in tasks.enumerated() {
            line("task index=\(index) title=\(String(reflecting: task.title)) owner=\(task.owner ?? "nil") deadline=\(task.deadlineText ?? "nil")")
        }
        for (index, decision) in decisions.enumerated() {
            line("decision index=\(index) text=\(String(reflecting: decision.text))")
        }
        for (index, issue) in openIssues.enumerated() {
            line("open_issue index=\(index) text=\(String(reflecting: issue.text))")
        }
        let agenda = (meeting.agendaText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        for (index, topic) in agenda.split(separator: "\n").enumerated() {
            line("agenda index=\(index) topic=\(String(reflecting: String(topic)))")
        }
        let summary = meeting.summary?.executiveSummary ?? ""
        line("summary=\(String(reflecting: summary))")
        for (index, point) in (meeting.summary?.keyPoints ?? []).enumerated() {
            line("discussion index=\(index) text=\(String(reflecting: point))")
        }
        if let minutes = analysis?.minutes {
            for (index, topic) in minutes.topics.enumerated() {
                line("topic index=\(index) title=\(String(reflecting: topic.title)) outcome=\(topic.outcome?.kind.rawValue ?? "none") bullets=\(topic.discussion.count)")
            }
            for (index, action) in minutes.actions.enumerated() {
                line("action index=\(index) title=\(String(reflecting: action.title)) owner=\(action.owner ?? "nil") deadline=\(action.deadlineText ?? "nil") due=\(action.dueDate ?? "nil")")
            }
            for (index, person) in minutes.suggestedAttendees.enumerated() {
                line("suggested_attendee index=\(index) name=\(person.name) reason=\(person.reason)")
            }
            if let next = minutes.nextMeeting { line("next_meeting text=\(String(reflecting: next.text))") }
        } else {
            line("minutes=missing")
        }
        let tasksOK = tasks.count == 2 && tasks.allSatisfy { $0.owner != nil }
        let decisionsOK = decisions.count == 2
        let openOK = openIssues.count >= 1
        let agendaOK = !agenda.isEmpty
        let lower = summary.lowercased()
        let summaryOK = !summary.isEmpty && !hasDevanagari(summary) && lower.contains("pune") && lower.contains("20")
        line("check pipeline=\(pipelineCompleted ? "ok" : "fail")")
        line("check tasks_with_owners=\(tasksOK ? "ok" : "fail") count=\(tasks.count)")
        line("check decisions=\(decisionsOK ? "ok" : "fail") count=\(decisions.count)")
        line("check open_issues=\(openOK ? "ok" : "fail") count=\(openIssues.count)")
        line("check agenda_filled=\(agendaOK ? "ok" : "fail")")
        line("check english_summary_with_both_decisions=\(summaryOK ? "ok" : "fail")")
        let passed = pipelineCompleted && tasksOK && decisionsOK && openOK && agendaOK && summaryOK
        line("result \(passed ? "PASS" : "FAIL")")
        return passed
    }
}

/// Final audio buffers from one spoken line. AVAudioPCMBuffer is not Sendable, so the hand-off is explicit.
private struct CapturedSpeech: @unchecked Sendable {
    let buffers: [AVAudioPCMBuffer]
}

private final class SpeechCaptureStore: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []
    private var finished = false

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        buffers.append(buffer)
        lock.unlock()
    }

    /// Returns the collected buffers once, then nil.
    func finish() -> [AVAudioPCMBuffer]? {
        lock.lock()
        defer { lock.unlock() }
        if finished { return nil }
        finished = true
        return buffers
    }
}

/// Synthesizes the scripted dialogue with AVSpeechSynthesizer.write into one 16 kHz mono .caf file.
@MainActor
enum HindiSpeechFixture {
    static let sampleRate: Double = 16_000

    static func render() async throws -> URL {
        let synthesizer = AVSpeechSynthesizer()
        let voices = pickVoices()
        let nehaName = voices.neha?.name ?? "none"
        let pawanName = voices.pawan?.name ?? "none"
        print("MEETMIND_HINDI voices neha=\(nehaName) pawan=\(pawanName)"); fflush(stdout)
        var output: [Float] = [Float](repeating: 0, count: Int(sampleRate * 0.3))
        let gap = [Float](repeating: 0, count: Int(sampleRate * 0.6))
        for line in HindiScript.lines {
            try Task.checkCancellation()
            let isNeha = line.speaker == 0
            let voice = isNeha ? voices.neha : voices.pawan
            let pitch: Float = isNeha ? 1.15 : 0.85
            let captured = await capture(line.text, voice: voice, pitch: pitch, on: synthesizer)
            let raw = samples(from: captured.buffers)
            output.append(contentsOf: resample(raw.samples, from: raw.rate, to: sampleRate))
            output.append(contentsOf: gap)
        }
        guard output.count > Int(sampleRate * 5) else {
            throw OfflineError.unavailable("The Hindi (India) voices produced no audio. Install a Hindi voice in Settings, Accessibility, Spoken Content.")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hindi-smoke-\(UUID().uuidString).caf")
        try write(output, to: url)
        print("MEETMIND_HINDI audio seconds=\(Int(Double(output.count) / sampleRate))"); fflush(stdout)
        return url
    }

    private static func pickVoices() -> (neha: AVSpeechSynthesisVoice?, pawan: AVSpeechSynthesisVoice?) {
        let hindi = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "hi-IN" }
        let female = hindi.first { $0.gender == .female }
        let male = hindi.first { $0.gender == .male }
        let fallback = hindi.first ?? AVSpeechSynthesisVoice(language: "hi-IN")
        let neha = female ?? fallback
        var pawan = male
        if pawan == nil { pawan = hindi.first { $0.identifier != neha?.identifier } }
        return (neha, pawan ?? fallback)
    }

    private static func capture(_ text: String, voice: AVSpeechSynthesisVoice?, pitch: Float,
                                on synthesizer: AVSpeechSynthesizer) async -> CapturedSpeech {
        await withCheckedContinuation { (continuation: CheckedContinuation<CapturedSpeech, Never>) in
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.pitchMultiplier = pitch
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
            let store = SpeechCaptureStore()
            let timeout = Task {
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                if let buffers = store.finish() { continuation.resume(returning: CapturedSpeech(buffers: buffers)) }
            }
            synthesizer.write(utterance, toBufferCallback: bufferCallback(store: store, timeout: timeout,
                                                                         continuation: continuation))
        }
    }

    /// Built outside the main actor because AVFoundation calls it on its own queue.
    private nonisolated static func bufferCallback(store: SpeechCaptureStore, timeout: Task<Void, Never>,
                                                   continuation: CheckedContinuation<CapturedSpeech, Never>) -> AVSpeechSynthesizer.BufferCallback {
        return { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 {
                if let buffers = store.finish() {
                    timeout.cancel()
                    continuation.resume(returning: CapturedSpeech(buffers: buffers))
                }
            } else {
                store.append(pcm)
            }
        }
    }

    private static func samples(from buffers: [AVAudioPCMBuffer]) -> (samples: [Float], rate: Double) {
        var output: [Float] = []
        var rate = 22_050.0
        for buffer in buffers {
            rate = buffer.format.sampleRate
            let count = Int(buffer.frameLength)
            if let floats = buffer.floatChannelData {
                let channel = floats[0]
                for index in 0..<count { output.append(channel[index]) }
            } else if let ints = buffer.int16ChannelData {
                let channel = ints[0]
                for index in 0..<count { output.append(Float(channel[index]) / 32768.0) }
            }
        }
        return (output, rate)
    }

    private static func resample(_ input: [Float], from source: Double, to target: Double) -> [Float] {
        guard !input.isEmpty, source > 0 else { return [] }
        if abs(source - target) < 1 { return input }
        let ratio = source / target
        let count = Int(Double(input.count) / ratio)
        var output = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let position = Double(index) * ratio
            let lower = Int(position)
            let fraction = Float(position - Double(lower))
            let first = input[min(lower, input.count - 1)]
            let second = input[min(lower + 1, input.count - 1)]
            output[index] = first + (second - first) * fraction
        }
        return output
    }

    private static func write(_ samples: [Float], to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            throw OfflineError.unavailable("Could not allocate the synthetic audio buffer.")
        }
        for index in 0..<samples.count { channel[index] = samples[index] }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        try file.write(from: buffer)
    }
}
