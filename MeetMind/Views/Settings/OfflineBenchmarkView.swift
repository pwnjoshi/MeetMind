import SwiftUI
import UniformTypeIdentifiers
import OfflineEngineKit

/// Qualification lab only. Results never write to Meeting/ActionItem entities.
@MainActor
struct OfflineBenchmarkView: View {
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
                    }.padding(.vertical, 4)
                }
            }
            Section("Local input") {
                Button("Choose audio file") { importAudio = true }.disabled(busy)
                Text(isSyntheticAudio ? "Uses a short synthetic English audio clip and synthetic Hinglish text for smoke testing. This does not measure real meeting quality." : "A local recording is selected. Analysis uses its transcript after a speech benchmark.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Use synthetic text fixture") {
                    turns = OfflineBenchmarkRunner.syntheticTurns
                    status = "Synthetic text selected. This cannot establish real meeting accuracy."
                }.disabled(busy)
            }
            Section {
                NavigationLink("Model and engine licenses") {
                    ScrollView { Text(OfflineModelStore.notices).font(.footnote).textSelection(.enabled).padding() }
                        .navigationTitle("Licenses")
                }
            }
            if !output.isEmpty {
                Section("Result — requires human review") {
                    Text(output).font(.footnote).textSelection(.enabled)
                }
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
        busy = true; progress = 0; output = ""
        UIApplication.shared.isIdleTimerDisabled = true
        operation = Task { @MainActor in
            defer { busy = false; UIApplication.shared.isIdleTimerDisabled = false }
            do { try await work() }
            catch is CancellationError {
                status = "Cancelled. Downloaded model files can be reused on retry."
                print("MEETMIND_BENCHMARK cancelled")
            }
            catch {
                status = error.localizedDescription
                // No error payload: a library error could contain input text.
                print("MEETMIND_BENCHMARK failed; inspect the on-device status")
            }
            await refresh()
        }
    }

    private func install(_ profile: ModelProfile) async throws {
        status = "Downloading \(profile.name)…"
        print("MEETMIND_BENCHMARK download \(profile.id)")
        try await OfflineModelStore.shared.install(profile) { value in
            Task { @MainActor in progress = value }
        }
        await refresh()
        progress = 1; status = "Download verified. Ready for offline benchmarking."
    }

    private func run(_ profile: ModelProfile) async throws {
        status = "Running \(profile.name) on this iPhone. Keep the app open."
        print("MEETMIND_BENCHMARK running \(profile.id)")
        let result = try await runner.run(profile: profile, audio: audio, turns: turns)
        try OfflineBenchmarkRunner.save(result)
        if !result.turns.isEmpty { turns = result.turns }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        output = String(decoding: try encoder.encode(result), as: UTF8.self)
        progress = 1
        status = "Finished in \(Int(result.elapsedSeconds)) seconds. This is a benchmark, not a quality qualification."
        print("MEETMIND_BENCHMARK completed \(profile.id) seconds=\(result.elapsedSeconds) sampledPeakBytes=\(result.sampledPeakFootprintBytes) thermal=\(result.thermalState)")
    }
}
