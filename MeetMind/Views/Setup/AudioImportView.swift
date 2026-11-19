import SwiftUI
import SwiftData
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
                        Label(selectedURL.lastPathComponent, systemImage: "waveform")
                            .foregroundStyle(.primary)
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
                Section("Details") {
                    DatePicker("Recorded", selection: $recordedAt, in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute])
                        .disabled(isProcessing)
                    Picker("Series", selection: $selectedSeriesID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(seriesOptions, id: \.id) { series in
                            Text(series.name).tag(Optional(series.id))
                        }
                    }
                    .disabled(isProcessing)
                    Button("New Series...") {
                        seriesNameDraft = newSeriesName
                        isNewSeriesPresented = true
                    }
                        .disabled(isProcessing)
                }
                Section {
                    if isProcessing { ProgressView("Saving audio on this iPhone...") }
                    processButton
                } footer: {
                    Text("Audio stays on this iPhone. Manent creates a meeting with a transcript and speakers to review.")
                }
            }
            .navigationTitle("Import Audio")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
                    selectedURL = urls.first
                    if viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
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
        Button("Import recording") {
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
        .disabled(selectedURL == nil || isProcessing)
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
    }
}
