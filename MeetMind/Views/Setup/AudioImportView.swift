import SwiftUI
import SwiftData
import AVFoundation
import UniformTypeIdentifiers

/// Audio file import view with drop-zone, fileImporter, status indicator, and transcription trigger
public struct AudioImportView: View {
    @Bindable var viewModel: MeetingSetupViewModel
    public var onImportComplete: ((Meeting) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    
    @State private var isPickerPresented: Bool = false
    @State private var selectedURL: URL? = nil
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false
    @State private var fileDetails = ""
    @State private var recordedAt = Date()
    @Query private var savedMeetings: [Meeting]
    @State private var selectedSeriesID: UUID?
    @State private var newSeriesID: UUID?
    @State private var newSeriesName = ""
    @State private var seriesNameDraft = ""
    @State private var isNewSeriesPresented = false
    
    public init(viewModel: MeetingSetupViewModel = MeetingSetupViewModel(), onImportComplete: ((Meeting) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onImportComplete = onImportComplete
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Bring a recording from Files into Manent.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                Section("Audio File") {
                    if let selectedURL {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedURL.lastPathComponent)
                            if !fileDetails.isEmpty { Text(fileDetails).font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }
                    Button(selectedURL == nil ? "Choose Audio File..." : "Choose Another File...") {
                        isPickerPresented = true
                    }
                    .disabled(isProcessing)
                }
                Section("Title") {
                    TextField("Meeting title", text: $viewModel.title)
                        .disabled(isProcessing)
                }
                Section {
                    DatePicker("Recorded", selection: $recordedAt, in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute])
                        .disabled(isProcessing)
                    Menu {
                        Picker("Series", selection: $selectedSeriesID) {
                            Text("None").tag(nil as UUID?)
                            ForEach(seriesOptions, id: \.id) { series in Text(series.name).tag(Optional(series.id)) }
                        }
                        Button("New Series…", systemImage: "plus") {
                            seriesNameDraft = ""
                            isNewSeriesPresented = true
                        }
                    } label: {
                        LabeledContent("Series") {
                            Text(seriesOptions.first { $0.id == selectedSeriesID }?.name ?? "None")
                            Image(systemName: "chevron.up.chevron.down").font(.caption)
                        }
                    }.disabled(isProcessing)
                } header: {
                    Text("Details")
                } footer: {
                    Text("Audio stays on this iPhone. Manent creates a meeting with a transcript and speakers to review.")
                }
                Section {
                    if isProcessing { ProgressView("Saving audio on this iPhone...") }
                    processButton
                }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            .textCase(nil)
            .tint(Theme.Colors.manentAccent)
            .task(id: selectedURL) { await loadFileDetails() }
            .navigationTitle("Import Audio")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back", systemImage: "chevron.left") { dismiss() }.labelStyle(.iconOnly)
                        .disabled(isProcessing)
                }
            }
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav],
                allowsMultipleSelection: false
            ) { res in
                switch res {
                case .success(let urls):
                    let oldTitle = selectedURL?.deletingPathExtension().lastPathComponent
                    selectedURL = urls.first
                    if viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.title == oldTitle,
                       let url = urls.first {
                        viewModel.title = url.deletingPathExtension().lastPathComponent
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
            .interactiveDismissDisabled(isProcessing)
            .alert("New Series", isPresented: $isNewSeriesPresented) {
                TextField("Series name", text: $seriesNameDraft)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    newSeriesName = seriesNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    let id = newSeriesID ?? UUID()
                    newSeriesID = id
                    selectedSeriesID = id
                }
                .disabled(seriesNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert("Import Failed", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Could not import audio.")
            }
        }
    }
    
    @MainActor
    private func loadFileDetails() async {
        fileDetails = ""
        guard let url = selectedURL else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var parts: [String] = []
        if let time = try? await AVURLAsset(url: url).load(.duration), time.seconds.isFinite, time.seconds > 0 {
            let seconds = Int(time.seconds.rounded())
            parts.append("\(seconds / 60) min \(seconds % 60) sec")
        }
        parts.append(url.pathExtension.uppercased())
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        if !Task.isCancelled, selectedURL == url { fileDetails = parts.joined(separator: " \u{00B7} ") }
    }

    private var seriesOptions: [(id: UUID, name: String)] {
        var names: [UUID: String] = [:]
        if let id = newSeriesID { names[id] = newSeriesName }
        for meeting in savedMeetings {
            if let id = meeting.seriesID, let name = meeting.seriesName, !name.isEmpty {
                names[id] = name
            }
        }
        return names.map { (id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var processButton: some View {
        Button {
            guard let url = selectedURL else { return }
            viewModel.importedRecordingDate = recordedAt
            viewModel.importedSeriesID = selectedSeriesID
            viewModel.importedSeriesName = seriesOptions.first { $0.id == selectedSeriesID }?.name
            isProcessing = true
            Task {
                do {
                    let meeting = try await viewModel.importAudioFile(url: url)
                    isProcessing = false
                    onImportComplete?(meeting)
                    dismiss()
                } catch {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
        label: {
            Text("Import Recording").frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(.white).background(Theme.Colors.manentAccent, in: Capsule())
        }
        .disabled(selectedURL == nil || isProcessing)
        .opacity(selectedURL == nil || isProcessing ? 0.5 : 1)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
    }
}
