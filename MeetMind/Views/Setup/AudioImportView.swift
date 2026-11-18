import SwiftUI
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
    
    public init(viewModel: MeetingSetupViewModel = MeetingSetupViewModel(), onImportComplete: ((Meeting) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onImportComplete = onImportComplete
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                AudioImportHeaderView()
                
                AudioDropZoneView(
                    selectedURL: selectedURL,
                    onSelect: { isPickerPresented = true },
                    onClear: { selectedURL = nil }
                )
                
                if isProcessing {
                    ProgressView("Saving audio on this iPhone…")
                        .tint(Theme.Colors.liveBlue)
                        .padding()
                }
                
                Spacer()
                
                processButton
            }
            .padding(Spacing.lg)
            .navigationTitle("Import Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
            .interactiveDismissDisabled(isProcessing)
            .alert("Import Failed", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Could not import audio.")
            }
        }
    }
    
    private var processButton: some View {
        Button("Import recording") {
            guard let url = selectedURL else { return }
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
