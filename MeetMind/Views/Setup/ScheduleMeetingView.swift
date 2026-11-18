import SwiftUI

/// Schedule Meeting view form with title, dates, template picker, agenda, and participants
public struct ScheduleMeetingView: View {
    @Bindable var viewModel: MeetingSetupViewModel
    public var onMeetingScheduled: ((Meeting) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showValidationError: Bool = false
    @State private var initialDraft: String?
    @State private var showsDiscardConfirmation = false
    
    public init(viewModel: MeetingSetupViewModel = MeetingSetupViewModel(), onMeetingScheduled: ((Meeting) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onMeetingScheduled = onMeetingScheduled
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Meeting Info") {
                    NavigationLink {
                        Form {
                            TextField("Meeting title", text: $viewModel.title)
                                .submitLabel(.done)
                        }
                        .navigationTitle("Meeting Title")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent("Title", value: viewModel.title.isEmpty ? "Required" : viewModel.title)
                    }
                    DatePicker("Start Time", selection: $viewModel.startDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End Time", selection: $viewModel.endDate, displayedComponents: [.date, .hourAndMinute])
                    if let err = viewModel.dateValidationError {
                        Text(err).font(Typography.caption).foregroundStyle(Theme.Colors.coralRed)
                    }
                }
                
                Section("Template") {
                    MeetingTemplatePicker(
                        templates: viewModel.availableTemplates,
                        selectedTemplate: viewModel.selectedTemplate,
                        onSelect: { template in
                            viewModel.attemptTemplateSwitch(to: template.type)
                        }
                    )
                }
                
                Section("Agenda") {
                    NavigationLink {
                        Form {
                            TextEditor(text: $viewModel.agendaText)
                                .frame(minHeight: 240)
                                .accessibilityLabel("Meeting agenda")
                        }
                        .navigationTitle("Meeting Agenda")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent("Agenda", value: viewModel.agendaText.isEmpty ? "Add agenda" : viewModel.agendaText)
                            .lineLimit(2)
                    }
                }
                
                Section("Participants") {
                    ParticipantManagerView(
                        participants: viewModel.participants,
                        onAddParticipant: { speaker in viewModel.addParticipant(speaker) },
                        onRemoveParticipant: { speaker in viewModel.removeParticipant(speaker) }
                    )
                }
            }
            .navigationTitle("Schedule Meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedChanges { showsDiscardConfirmation = true }
                        else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        do {
                            let meeting = try viewModel.saveScheduledMeeting()
                            onMeetingScheduled?(meeting)
                            dismiss()
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                            showValidationError = true
                        }
                    }
                    .disabled(!viewModel.isFormValid)
                    .fontWeight(.semibold)
                }
            }
            .alert("Invalid Input", isPresented: $showValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Please check meeting title and dates.")
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .onAppear { if initialDraft == nil { initialDraft = draftSignature } }
            .alert("Discard meeting changes?", isPresented: $showsDiscardConfirmation) {
                Button("Keep Editing", role: .cancel) { }
                Button("Discard Changes", role: .destructive) { dismiss() }
            } message: { Text("The meeting has not been saved.") }
            .alert("Overwrite Custom Agenda?", isPresented: $viewModel.isShowingTemplateOverwriteConfirmation) {
                Button("Overwrite", role: .destructive) { viewModel.confirmTemplateSwitch() }
                Button("Cancel", role: .cancel) { viewModel.cancelTemplateSwitch() }
            } message: {
                Text("Choosing this template will replace custom agenda notes. Do you want to continue?")
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        initialDraft.map { $0 != draftSignature } ?? false
    }

    private var draftSignature: String {
        [viewModel.title, viewModel.agendaText,
         String(viewModel.startDate.timeIntervalSince1970),
         String(viewModel.endDate.timeIntervalSince1970),
         viewModel.participants.map { $0.id.uuidString }.sorted().joined(separator: ",")]
            .joined(separator: "\u{001F}")
    }
}
