import SwiftUI
import UniformTypeIdentifiers
import OfflineEngineKit
import Darwin
import SwiftData

/// Qualification lab only. Results never write to Meeting/ActionItem entities.
@MainActor
struct OfflineBenchmarkView: View {
    @Query(sort: \Meeting.createdAt, order: .reverse) private var savedMeetings: [Meeting]
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var nemotronTranscript: String?
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
            Section("Nemotron live caption replay") {
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
                Button("Replay with Nemotron") {
                    begin {
                        nemotronTranscript = nil
                        status = "Replaying with Nemotron…"
                        let result = try await NemotronCaptionReplay.run(
                            audio: audio, model: URL(fileURLWithPath: nemotronModelPath))
                        nemotronTranscript = result.text
                        if let delay = result.firstPartialSeconds {
                            status = "Nemotron finished. First caption after \(delay.formatted(.number.precision(.fractionLength(2)))) seconds."
                        } else {
                            status = "Nemotron finished without a partial caption."
                        }
                    }
                }
                .disabled(nemotronModelPath.isEmpty)
                if let nemotronTranscript {
                    Text(nemotronTranscript.isEmpty ? "No speech recognized." : nemotronTranscript)
                        .textSelection(.enabled)
                }
            }
            .disabled(busy)
            Section("Local input") {
                if !savedMeetings.filter({ $0.audioFileURL != nil }).isEmpty {
                    Menu("Use a saved MeetMind recording") {
                        ForEach(savedMeetings.filter { $0.audioFileURL != nil }) { meeting in
                            Button(meeting.title) {
                                guard let recording = meeting.resolvedAudioFileURL,
                                      FileManager.default.fileExists(atPath: recording.path) else {
                                    status = "This recording file is unavailable."
                                    return
                                }
                                audio = recording
                                isSyntheticAudio = false
                                turns = []
                                output = ""
                                lastResult = nil
                                status = "Saved recording selected. Run a speech benchmark before task analysis."
                            }
                        }
                    }.disabled(busy)
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
        .onDisappear { operation?.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && busy { operation?.cancel() }
        }
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
