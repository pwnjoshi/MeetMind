import SwiftUI
import SwiftData

/// New Meeting launcher presenting options for instant meeting, scheduling, or importing audio
public struct NewMeetingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: MeetingSetupViewModel
    public var onMeetingCreated: ((Meeting) -> Void)? = nil
    
    @State private var showScheduleForm: Bool = false
    @State private var showAudioImport: Bool = false
    
    public init(modelContext: ModelContext? = nil, viewModel: MeetingSetupViewModel? = nil, onMeetingCreated: ((Meeting) -> Void)? = nil) {
        let vm = viewModel ?? MeetingSetupViewModel(modelContext: modelContext)
        _viewModel = State(initialValue: vm)
        self.onMeetingCreated = onMeetingCreated
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.xs) {
                    Text("Start a Meeting").font(Typography.title2).foregroundStyle(Theme.Colors.textPrimary)
                    Text("Choose how you would like to capture or organize your meeting.")
                        .font(Typography.subheadline).foregroundStyle(Theme.Colors.textSecondary).multilineTextAlignment(.center)
                }
                .padding(.top, Spacing.lg)
                
                VStack(spacing: Spacing.md) {
                    NewMeetingOptionCard(
                        title: "Instant Live Meeting",
                        subtitle: "Start recording immediately with real-time speech transcription.",
                        iconName: "record.circle.fill",
                        tintColor: Theme.Colors.coralRed,
                        backgroundColor: Theme.Colors.coralRedLight
                    ) {
                        let meeting = viewModel.quickStartMeeting()
                        onMeetingCreated?(meeting)
                        dismiss()
                    }
                    
                    NewMeetingOptionCard(
                        title: "Schedule Meeting",
                        subtitle: "Plan ahead with meeting agendas, attendee tags, and built-in templates.",
                        iconName: "calendar.badge.plus",
                        tintColor: Theme.Colors.warmAmber,
                        backgroundColor: Theme.Colors.warmAmberLight
                    ) { showScheduleForm = true }
                    
                    NewMeetingOptionCard(
                        title: "Import Audio File",
                        subtitle: "Transcribe and analyze existing audio files (.m4a, .mp3, .wav).",
                        iconName: "waveform.badge.plus",
                        tintColor: Theme.Colors.liveBlue,
                        backgroundColor: Theme.Colors.liveBlueLight
                    ) { showAudioImport = true }
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showScheduleForm) {
                ScheduleMeetingView(viewModel: viewModel) { meeting in
                    onMeetingCreated?(meeting)
                    dismiss()
                }
                .environment(\.modelContext, modelContext)
            }
            .sheet(isPresented: $showAudioImport) {
                AudioImportView(viewModel: viewModel) { meeting in
                    onMeetingCreated?(meeting)
                    dismiss()
                }
                .environment(\.modelContext, modelContext)
            }
            .onAppear { viewModel.setModelContext(modelContext) }
        }
        .presentationDetents([.medium, .large])
    }
}
