import SwiftUI

/// Schedule Meeting view form with title, dates, template picker, agenda, and participants
public struct ScheduleMeetingView: View {
    @Bindable var viewModel: MeetingSetupViewModel
    public var onMeetingScheduled: ((Meeting) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showValidationError: Bool = false
    
    public init(viewModel: MeetingSetupViewModel = MeetingSetupViewModel(), onMeetingScheduled: ((Meeting) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onMeetingScheduled = onMeetingScheduled
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Meeting Info") {
                    TextField("Meeting Title", text: $viewModel.title)
                        .font(Typography.body)
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
                    TextEditor(text: $viewModel.agendaText)
                        .frame(minHeight: 80)
                        .font(Typography.body)
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
                    Button("Cancel") { dismiss() }
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
            .alert("Overwrite Custom Agenda?", isPresented: $viewModel.isShowingTemplateOverwriteConfirmation) {
                Button("Overwrite", role: .destructive) { viewModel.confirmTemplateSwitch() }
                Button("Cancel", role: .cancel) { viewModel.cancelTemplateSwitch() }
            } message: {
                Text("Choosing this template will replace custom agenda notes. Do you want to continue?")
            }
        }
    }
}
