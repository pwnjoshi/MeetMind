import SwiftUI
import AVFoundation
import Speech
import UniformTypeIdentifiers
import OfflineEngineKit
import Darwin
import SwiftData

/// Qualification lab only. Results never write to Meeting/ActionItem entities.
@MainActor
struct OfflineBenchmarkView: View {
    @Query(sort: \Meeting.createdAt, order: .reverse) private var savedMeetings: [Meeting]
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState: AppState?
    @State private var profiles: [ModelProfile] = []
    @State private var installed: Set<String> = []
    @State private var operation: Task<Void, Never>?
    @State private var busy = false
    @State private var progress: Double = 0
    @State private var status = "Models have not been qualified yet."
    @State private var audio = OfflineBenchmarkRunner.syntheticAudioURL
    @State private var isSyntheticAudio = true
    @State private var importAudio = false
    @State private var turns = OfflineBenchmarkRunner.syntheticTurns
    @State private var output = ""
    @State private var lastResult: BenchmarkResult?
    @AppStorage("NemotronCaptionLabModelPath") private var nemotronModelPath = ""
    @AppStorage("UseNemotronLiveCaptions") private var useNemotronLiveCaptions = false
    @State private var nemotronTranscript: String?
    @State private var appleTranscript: String?
    @State private var appleReplayError: String?
    @State private var nemotronReplayError: String?
    @State private var appleMeasurement: ReplayMeasurement?
    @State private var nemotronMeasurement: ReplayMeasurement?
    @State private var referenceTranscript = ""
    @State private var appleFirstCaption: Double?
    @State private var nemotronFirstCaption: Double?
    @AppStorage("PinnedCaptionBenchmarkRecording") private var pinnedRecording = ""
    @State private var selectedRecording: Meeting?
    private let runner = OfflineBenchmarkRunner()

    var body: some View {
        List {
            Section {
                Text("Offline model qualification").font(.headline)
                Text("Meeting content stays on this iPhone. Downloads contain public models only. Benchmark results do not create tasks or change saved meetings.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(status).accessibilityIdentifier("benchmark.status")
                if busy {
                    ProgressView(value: progress)
                    Button("Cancel", role: .cancel) { operation?.cancel(); status = "Cancelling…" }
                }
            }
            Section("Models") {
                ForEach(profiles) { profile in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(profile.name).font(.subheadline)
                        Text(ByteCountFormatter.string(fromByteCount: profile.downloadBytes, countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(installed.contains(profile.id) ? "Verify / download again" : "Download") {
                                begin { try await install(profile) }
                            }
                            .buttonStyle(.bordered)
                            if installed.contains(profile.id) {
                                Button("Run benchmark") { begin { try await run(profile) } }
                                    .buttonStyle(.borderedProminent)
                            }
                        }.disabled(busy)
                        if installed.contains(profile.id) {
                            Button("Remove downloaded model", role: .destructive) {
                                begin {
                                    try await OfflineModelStore.shared.remove(profile)
                                    status = "Model files removed. You can download them again."
                                }
                            }
                            .font(.caption).buttonStyle(.borderless).disabled(busy)
                        }
                    }.padding(.vertical, 4)
                }
            }
            Section("Live caption comparison") {
                Text("Experimental. Replays the selected local recording at recording speed.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Download Nemotron") {
                    begin {
                        status = "Downloading Nemotron…"
                        let folder = try await NemotronCaptionReplay.download { value in
                            Task { @MainActor in progress = value }
                        }
                        nemotronModelPath = folder.path
                        status = "Nemotron is ready for replay."
                    }
                }
                Toggle("Use Nemotron for mixed-language recording captions", isOn: $useNemotronLiveCaptions)
                    .disabled(nemotronModelPath.isEmpty)
                Button("Replay with Apple Speech") {
                    begin { try await runAppleReplay() }
                }
                Button("Replay with Nemotron") {
                    begin { try await runNemotronReplay() }
                }
                .disabled(nemotronModelPath.isEmpty)
                Button("Compare both engines") {
                    begin { try await compareCaptionEngines() }
                }
                .disabled(nemotronModelPath.isEmpty)
                TextField("Verified reference transcript or excerpt", text: $referenceTranscript, axis: .vertical)
                    .lineLimit(2...5)
                Text("Enter the verified words for the selected recording. For an excerpt, replay the matching audio clip. Scoring supports up to 1,000 words per transcript.")
                    .font(.caption).foregroundStyle(.secondary)
                if let appleReplayError {
                    Text("Apple Speech: \(appleReplayError)").font(.caption)
                }
                if let nemotronReplayError {
                    Text("Nemotron: \(nemotronReplayError)").font(.caption)
                }
                if let appleTranscript {
                    replayResult("Apple Speech", transcript: appleTranscript, delay: appleFirstCaption, measurement: appleMeasurement)
                }
                if let nemotronTranscript {
                    replayResult("Nemotron", transcript: nemotronTranscript, delay: nemotronFirstCaption, measurement: nemotronMeasurement)
                }
            }
            .disabled(busy)
            Section("Local input") {
                if !savedMeetings.filter({ $0.audioFileURL != nil }).isEmpty {
                    Menu("Use a saved MeetMind recording") {
                        ForEach(savedMeetings.filter { $0.audioFileURL != nil }) { meeting in
                            Button(meeting.title) { selectRecording(meeting) }
                        }
                    }.disabled(busy)
                }
                if !pinnedRecording.isEmpty {
                    Button("Use pinned recording") {
                        if let meeting = savedMeetings.first(where: { recordingKey($0) == pinnedRecording }) {
                            selectRecording(meeting)
                        } else {
                            status = "The pinned audio is unavailable. Select and pin another recording."
                        }
                    }
                    .disabled(busy)
                }
                if let selectedRecording, let key = recordingKey(selectedRecording), key != pinnedRecording {
                    Button("Pin \(selectedRecording.title) for replay") {
                        pinnedRecording = key
                        status = "Pinned \(selectedRecording.title) for future replays."
                    }
                    .disabled(busy)
                }
                Button("Choose audio file") { importAudio = true }.disabled(busy)
                Text(isSyntheticAudio ? "Uses a short synthetic English audio clip and synthetic Hinglish text for smoke testing. This does not measure real meeting quality." : "A local recording is selected. Analysis uses its transcript after a speech benchmark.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Use synthetic text fixture") {
                    turns = OfflineBenchmarkRunner.syntheticTurns
                    output = ""
                    lastResult = nil
                    status = "Synthetic text selected. This cannot establish real meeting accuracy."
                }.disabled(busy)
            }
            Section {
                NavigationLink("Model and engine licenses") {
                    ScrollView { Text(OfflineModelStore.notices).font(.footnote).textSelection(.enabled).padding() }
                        .navigationTitle("Licenses")
                }
            }
            if let lastResult {
                OfflineBenchmarkResultsView(result: lastResult, rawJSON: output)
            }
        }
        .navigationTitle("Offline Benchmarks")
        .fileImporter(isPresented: $importAudio, allowedContentTypes: [.audio]) { result in
            do {
                let source = try result.get()
                guard source.startAccessingSecurityScopedResource() else {
                    throw OfflineError.unavailable("Unable to access the selected audio file.")
                }
                defer { source.stopAccessingSecurityScopedResource() }
                let destination = try OfflineModelStore.privateDirectory("Inputs")
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
                try FileManager.default.copyItem(at: source, to: destination)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
                audio = destination
                selectedRecording = nil
                isSyntheticAudio = false
                turns = []
                output = ""
                lastResult = nil
                status = "Local recording ready. Run a speech or speaker benchmark."
            } catch { status = error.localizedDescription }
        }
        .task {
            do {
                profiles = try OfflineModelStore.profiles()
                await refresh()
                let arguments = ProcessInfo.processInfo.arguments
                if let argument = arguments.first(where: { $0.hasPrefix("--benchmark-model=") }),
                   let profile = profiles.first(where: { $0.id == String(argument.dropFirst("--benchmark-model=".count)) }) {
                    begin {
                        if !installed.contains(profile.id) { try await install(profile) }
                        try await run(profile)
                    }
                }
            } catch { status = error.localizedDescription }
        }
        .onChange(of: audio) { _, _ in
            appleTranscript = nil
            nemotronTranscript = nil
            referenceTranscript = ""
            appleReplayError = nil
            nemotronReplayError = nil
        }
        .onDisappear { operation?.cancel() }
        .onChange(of: appState?.isRecordingActive) { _, active in
            if active == true { operation?.cancel() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && busy { operation?.cancel() }
        }
    }

    private func recordingKey(_ meeting: Meeting) -> String? {
        guard let file = meeting.resolvedAudioFileURL else { return nil }
        return meeting.id.uuidString + "/" + file.lastPathComponent
    }

    private func selectRecording(_ meeting: Meeting) {
        guard let recording = meeting.resolvedAudioFileURL,
              FileManager.default.fileExists(atPath: recording.path) else {
            status = "This recording file is unavailable."
            return
        }
        audio = recording
        selectedRecording = meeting
        isSyntheticAudio = false
        turns = []
        output = ""
        lastResult = nil
        status = "Selected \(meeting.title)."
    }

    private func replayResult(_ engine: String, transcript: String, delay: Double?,
                              measurement: ReplayMeasurement?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(engine).font(.headline)
            if let delay {
                Text("First caption after \(delay.formatted(.number.precision(.fractionLength(2)))) seconds.")
                    .font(.caption)
            }
            if let measurement {
                Text("Total \(measurement.elapsed.formatted(.number.precision(.fractionLength(1)))) seconds · Peak \(measurement.memoryText) · Thermal \(measurement.thermal)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let score = CaptionReplayScore.compare(reference: referenceTranscript, transcript: transcript) {
                Text("Word error rate \(score.rate.formatted(.percent.precision(.fractionLength(1))))")
                    .font(.caption)
                Text("\(score.substitutions) substitutions · \(score.deletions) omissions · \(score.insertions) additions")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(transcript.isEmpty ? "No finalized speech recognized." : transcript).textSelection(.enabled)
        }
    }

    private func compareCaptionEngines() async throws {
        appleTranscript = nil
        nemotronTranscript = nil
        appleReplayError = nil
        nemotronReplayError = nil
        do {
            try await runAppleReplay()
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            appleReplayError = error.localizedDescription
        }
        try Task.checkCancellation()
        do {
            try await runNemotronReplay()
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            nemotronReplayError = error.localizedDescription
        }
        status = appleReplayError == nil && nemotronReplayError == nil
            ? "Both caption replays finished."
            : "Comparison finished with an engine failure."
    }

    private func runNemotronReplay() async throws {
        nemotronReplayError = nil
        nemotronTranscript = nil
        nemotronMeasurement = nil
        nemotronMeasurement = try await measureReplay { try await replayNemotron() }
    }

    private func replayNemotron() async throws {
        nemotronTranscript = nil
        status = "Replaying with Nemotron…"
        let result = try await NemotronCaptionReplay.run(
            audio: audio, model: URL(fileURLWithPath: nemotronModelPath))
        nemotronTranscript = result.text
        nemotronFirstCaption = result.firstPartialSeconds
        status = "Nemotron replay finished."
    }

    private func runAppleReplay() async throws {
        appleReplayError = nil
        appleTranscript = nil
        appleMeasurement = nil
        appleMeasurement = try await measureReplay { try await replayApple() }
    }

    private func replayApple() async throws {
        appleTranscript = nil
        appleFirstCaption = nil
        status = "Replaying with Apple Speech…"
        let service = SpeechTranscriptionService()
        service.usesExperimentalCaptionEngine = false
        guard await service.requestAuthorization() == .authorized else {
            throw SpeechTranscriptionError.authorizationDenied
        }
        let input = audio
        let clock = ContinuousClock()
        let (stream, feed) = AsyncStream<AVAudioPCMBuffer>.makeStream(bufferingPolicy: .bufferingOldest(20))
        let captions = service.startLiveTranscription(audioBufferStream: stream)
        let started = clock.now
        let producer = Task.detached {
            defer { feed.finish() }
            let file = try AVAudioFile(forReading: input)
            let format = file.processingFormat
            let frames = AVAudioFrameCount(max(1, format.sampleRate / 10))
            while file.framePosition < file.length {
                try Task.checkCancellation()
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
                    throw OfflineError.unavailable("Unable to allocate a replay buffer.")
                }
                try file.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                let seconds = Double(file.framePosition) / format.sampleRate
                try await clock.sleep(until: started.advanced(by: .seconds(seconds)))
                switch feed.yield(buffer) {
                case .enqueued: break
                case .dropped: throw OfflineError.unavailable("Apple Speech fell behind the replay.")
                case .terminated: throw CancellationError()
                @unknown default: throw OfflineError.unavailable("Unable to feed Apple Speech.")
                }
            }
        }
        defer {
            producer.cancel()
            service.stopLiveTranscription()
        }
        var finalized: [String] = []
        var notice: String?
        for try await caption in captions where !caption.text.isEmpty {
            try Task.checkCancellation()
            // Engine notices use the same stream but carry no timed speech.
            guard !caption.segments.isEmpty else {
                if !caption.isFinal { notice = caption.text }
                continue
            }
            if appleFirstCaption == nil {
                let elapsed = (clock.now - started).components
                appleFirstCaption = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            }
            if caption.isFinal { finalized.append(caption.text) }
        }
        try await producer.value
        try Task.checkCancellation()
        if finalized.isEmpty, let notice {
            throw SpeechTranscriptionError.recognitionRequestFailed(notice)
        }
        appleTranscript = finalized.joined(separator: " ")
        status = "Apple Speech replay finished."
    }

    private struct ReplayMeasurement {
        let elapsed: Double
        let peakBytes: UInt64
        let thermal: String

        var memoryText: String {
            guard peakBytes > 0 else { return "unavailable" }
            return ByteCountFormatter.string(fromByteCount: Int64(clamping: peakBytes), countStyle: .memory)
        }
    }

    private func measureReplay(_ run: () async throws -> Void) async throws -> ReplayMeasurement {
        guard appState?.isRecordingActive != true, !OfflineProcessingGate.isProcessing else {
            throw OfflineError.unavailable("Finish recording or meeting processing before replaying audio.")
        }
        OfflineProcessingGate.begin()
        defer { OfflineProcessingGate.end() }

        let started = Date()
        let sampler = Task.detached(priority: .utility) {
            var peak = OfflineBenchmarkRunner.currentFootprintBytes()
            while !Task.isCancelled {
                peak = max(peak, OfflineBenchmarkRunner.currentFootprintBytes())
                try? await Task.sleep(for: .milliseconds(250))
            }
            return peak
        }
        defer { sampler.cancel() }
        try await run()
        sampler.cancel()
        let sampled = await sampler.value
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        return ReplayMeasurement(elapsed: Date().timeIntervalSince(started),
                                 peakBytes: max(sampled, OfflineBenchmarkRunner.currentFootprintBytes()),
                                 thermal: thermal)
    }

    private func refresh() async {
        var ready: Set<String> = []
        for profile in profiles {
            if await OfflineModelStore.shared.isInstalled(profile) { ready.insert(profile.id) }
        }
        installed = ready
    }

    private func begin(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; progress = 0; output = ""; lastResult = nil
        UIApplication.shared.isIdleTimerDisabled = true
        operation = Task { @MainActor in
            defer { busy = false; UIApplication.shared.isIdleTimerDisabled = false }
            do { try await work() }
            catch is CancellationError {
                status = "Cancelled. Downloaded model files can be reused on retry."
                print("MEETMIND_BENCHMARK cancelled")
                fflush(stdout)
            }
            catch {
                status = error.localizedDescription
                if let offlineError = error as? OfflineError,
                   case let .memoryBudget(requiredEstimate, budget) = offlineError {
                    print("MEETMIND_BENCHMARK rejected_memory estimatedBytes=\(requiredEstimate) budgetBytes=\(budget)")
                }
                // No error payload: a library error could contain input text.
                print("MEETMIND_BENCHMARK failed; inspect the on-device status")
                fflush(stdout)
            }
            await refresh()
        }
    }

    private func install(_ profile: ModelProfile) async throws {
        status = "Downloading \(profile.name)…"
        print("MEETMIND_BENCHMARK download \(profile.id)")
        fflush(stdout)
        try await OfflineModelStore.shared.install(profile) { value in
            Task { @MainActor in progress = value }
        }
        await refresh()
        progress = 1; status = "Download verified. Ready for offline benchmarking."
    }

    private func run(_ profile: ModelProfile) async throws {
        status = "Running \(profile.name) on this iPhone. Keep the app open."
        print("MEETMIND_BENCHMARK running \(profile.id)")
        fflush(stdout)
        let result = try await runner.run(profile: profile, audio: audio, turns: turns)
        try OfflineBenchmarkRunner.save(result)
        if !result.turns.isEmpty { turns = result.turns }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        output = String(decoding: try encoder.encode(result), as: UTF8.self)
        lastResult = result
        progress = 1
        status = "Finished in \(Int(result.elapsedSeconds)) seconds. This is a benchmark, not a quality qualification."
        print("MEETMIND_BENCHMARK completed \(profile.id) seconds=\(result.elapsedSeconds) sampledPeakBytes=\(result.sampledPeakFootprintBytes) thermal=\(result.thermalState)")
        fflush(stdout)
    }
}

/// All review content is rendered on the phone, never sent through USB telemetry.
private struct OfflineBenchmarkResultsView: View {
    let result: BenchmarkResult
    let rawJSON: String

    var body: some View {
        Group {
            Section("Benchmark result") {
                Text("\(Int(result.elapsedSeconds)) seconds · \(ByteCountFormatter.string(fromByteCount: Int64(clamping: result.sampledPeakFootprintBytes), countStyle: .memory)) sampled peak")
                    .font(.footnote)
                Text("Review accuracy below. These results do not create active tasks.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !result.turns.isEmpty {
                Section("Transcript") {
                    ForEach(result.turns) { turn in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(time(turn.start)) · \(turn.speaker ?? "Speaker not identified")")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(turn.text).textSelection(.enabled)
                        }
                    }
                }
            }
            if !result.speakers.isEmpty {
                Section("Speaker timeline") {
                    ForEach(Array(result.speakers.enumerated()), id: \.offset) { _, span in
                        Text("\(span.speaker): \(time(span.start))–\(time(span.end))")
                    }
                }
            }
            let discussion = result.analysis.flatMap(\.discussion)
            if !discussion.isEmpty {
                Section("Discussion") {
                    ForEach(Array(discussion.enumerated()), id: \.offset) { _, point in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(point.text)
                            evidence(point.evidence)
                        }
                    }
                }
            }
            let decisions = result.analysis.flatMap(\.decisions)
            if !result.analysis.isEmpty {
                Section("Decisions") {
                    if decisions.isEmpty { Text("No decisions extracted.").foregroundStyle(.secondary) }
                    ForEach(Array(decisions.enumerated()), id: \.offset) { _, point in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(point.text)
                            evidence(point.evidence)
                        }
                    }
                }
                let tasks = result.analysis.flatMap(\.tasks)
                Section("Suggested tasks — review required") {
                    if tasks.isEmpty { Text("No tasks extracted.").foregroundStyle(.secondary) }
                    ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(task.title).font(.headline)
                            Text("\(task.category) · \(task.owner ?? "Unassigned")")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let deadline = task.deadlineText { Text("Deadline wording: \(deadline)").font(.footnote) }
                            if let priority = task.priority { Text("Priority: \(priority)").font(.footnote) }
                            evidence(task.evidence)
                        }
                    }
                }
            }
            Section {
                DisclosureGroup("Technical benchmark data") {
                    Text(rawJSON).font(.caption).textSelection(.enabled)
                }
            }
        }
    }

    private func evidence(_ items: [SourceEvidence]) -> some View {
        DisclosureGroup("Source evidence") {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text("\(item.turnID): \(item.quote)").font(.footnote).textSelection(.enabled)
            }
        }.font(.footnote)
    }

    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds <= 86_400 else { return "—" }
        return String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}


private struct CaptionReplayScore {
    var substitutions = 0
    var deletions = 0
    var insertions = 0
    var referenceCount = 1
    var errors: Int { substitutions + deletions + insertions }
    var rate: Double { Double(errors) / Double(referenceCount) }

    static func compare(reference: String, transcript: String) -> Self? {
        func words(_ text: String) -> [Substring] {
            text.precomposedStringWithCanonicalMapping.lowercased().split { character in
                !character.isLetter && !character.isNumber
            }
        }
        let expected = words(reference)
        let actual = words(transcript)
        guard !expected.isEmpty, expected.count <= 1_000, actual.count <= 1_000 else { return nil }
        var previous = (0...actual.count).map { Self(insertions: $0) }
        var current = previous
        for (row, word) in expected.enumerated() {
            current[0] = Self(deletions: row + 1)
            for (column, spoken) in actual.enumerated() {
                if word == spoken {
                    current[column + 1] = previous[column]
                    continue
                }
                var best = previous[column]
                best.substitutions += 1
                var deletion = previous[column + 1]
                deletion.deletions += 1
                if deletion.errors < best.errors { best = deletion }
                var insertion = current[column]
                insertion.insertions += 1
                if insertion.errors < best.errors { best = insertion }
                current[column + 1] = best
            }
            swap(&previous, &current)
        }
        var result = previous[actual.count]
        result.referenceCount = expected.count
        return result
    }
}
