import SwiftUI

/// Confirm Assignment, Request a Correction, and Response Recorded, as one pushed page.
/// The local user records what the task owner told them. Nothing is sent or received by the app.
struct TaskAssignmentResponseView: View {
    private enum Step {
        case confirm
        case correction
        case recorded
    }

    let item: ActionItem
    let ownerName: String
    let onRecorded: (TaskResponse) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .confirm
    @State private var correctionText = ""
    @State private var recorded: TaskResponse?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch step {
            case .confirm: confirmStep
            case .correction: correctionStep
            case .recorded: recordedStep
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(step != .confirm)
        .toolbar {
            if step == .correction {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", systemImage: "chevron.left") { step = .confirm }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .alert("Could Not Save Response", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Steps

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Confirm Assignment", subtitle: "Owner: \(ownerName)")
            ActionFormCard {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                    if let due = item.dueDate {
                        Text("Due \(ActionListLogic.shortDate(due))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            Text("Use this after \(ownerName) tells you their answer. The app does not send anything or receive replies.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            Spacer()
            Button {
                record(TaskResponse(kind: .confirmed))
            } label: {
                Text("Record Confirmation")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            Button("Record a Correction Request") { step = .correction }
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.bottom, 8)
        }
    }

    private var correctionStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Request a Correction", subtitle: "Write down the change \(ownerName) asked for.")
            Text("Correction")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            ActionFormCard {
                TextField("Please move the deadline to Monday.", text: $correctionText, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            Spacer()
            Button {
                record(TaskResponse(kind: .correctionRequested, correctionText: correctionText.trimmingCharacters(in: .whitespacesAndNewlines)))
            } label: {
                Text("Save Request")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(correctionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.bottom, 8)
        }
    }

    private var recordedStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Response Recorded")
                    .font(.title3.bold())
                Text("Your note is saved on this iPhone. Nothing was sent to \(ownerName).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                if let recorded {
                    ShareLink(item: recorded.shareText(taskTitle: item.title, ownerName: ownerName)) {
                        Label("Share a Message", systemImage: "square.and.arrow.up")
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Return to Assignment")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.bottom, 8)
        }
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private func record(_ response: TaskResponse) {
        do {
            try TaskResponseStore.shared.record(response, for: item.id)
            recorded = response
            onRecorded(response)
            step = .recorded
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
