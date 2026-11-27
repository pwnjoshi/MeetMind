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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    fileSection
                    titleSection
                    detailsSection
                    if isProcessing {
                        ProgressView("Saving audio on this iPhone...")
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PrepStyle.background.ignoresSafeArea())
            .tint(Theme.Colors.manentAccent)
            .task(id: selectedURL) { await loadFileDetails() }
            .navigationTitle("Import Audio")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    PrepCloseButton { dismiss() }
                        .disabled(isProcessing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    PrepConfirmButton(isEnabled: selectedURL != nil && !isProcessing) { startImport() }
                }
            }            .fileImporter(
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
                Button("Create") {
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

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PrepSectionLabel(text: "FILE").font(.footnote)
            PrepCard {
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .foregroundStyle(Theme.Colors.manentAccent)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedURL?.lastPathComponent ?? "No file chosen")
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if selectedURL != nil, !fileDetails.isEmpty {
                            Text(fileDetails)
                                .font(.subheadline)
                                .foregroundStyle(PrepStyle.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Button(selectedURL == nil ? "Choose" : "Replace") { isPickerPresented = true }
                        .foregroundStyle(Theme.Colors.manentAccent)
                        .disabled(isProcessing)
                        .accessibilityLabel(selectedURL == nil ? "Choose audio file" : "Replace audio file")
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 60)
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PrepSectionLabel(text: "MEETING").font(.footnote)
            PrepCard {
                TextField("Meeting title", text: $viewModel.title)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .disabled(isProcessing)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PrepCard {
                HStack(spacing: 12) {
                    Image(systemName: "calendar").foregroundStyle(.red).frame(width: 24)
                        .accessibilityHidden(true)
                    DatePicker("Recorded", selection: $recordedAt, in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute])
                        .disabled(isProcessing)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                Divider().padding(.leading, 52)
                seriesMenu
            }
            Text("Audio stays on this iPhone. Import creates a new meeting.")
                .font(.footnote)
                .foregroundStyle(PrepStyle.secondaryText)
                .padding(.horizontal, 16)
        }
    }

    private var seriesMenu: some View {
        Menu {
            Picker("Series", selection: $selectedSeriesID) {
                Text("None").tag(nil as UUID?)
                ForEach(seriesOptions, id: \.id) { series in Text(series.name).tag(Optional(series.id)) }
            }
            Button("New Series\u{2026}") {
                seriesNameDraft = ""
                isNewSeriesPresented = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "repeat").foregroundStyle(Theme.Colors.manentAccent).frame(width: 24)
                    .accessibilityHidden(true)
                Text("Series").foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(seriesOptions.first { $0.id == selectedSeriesID }?.name ?? "None")
                    .foregroundStyle(PrepStyle.secondaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .disabled(isProcessing)
    }

    private func startImport() {
        guard let url = selectedURL, !isProcessing else { return }
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
}