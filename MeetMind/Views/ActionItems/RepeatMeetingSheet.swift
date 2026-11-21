import SwiftUI
import SwiftData

/// "Repeat" sheet: Never or Every Week. Every Week schedules the next occurrence
/// on this iPhone as a scheduled meeting in the same series.
struct RepeatMeetingSheet: View {
    let meeting: Meeting
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var selection: MeetingRepeatOption = .never
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ActionFormCard {
                        ForEach(Array(MeetingRepeatOption.allCases.enumerated()), id: \.element.id) { index, option in
                            Button {
                                selection = option
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.title).foregroundStyle(.primary)
                                        if option == .everyWeek {
                                            Text(MeetingRepeatService.weeklySubtitle(for: meeting))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if selection == option {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.Colors.manentAccent)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 52)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < MeetingRepeatOption.allCases.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    Text("Every Week adds the next \(meeting.title) to your Meetings list on this iPhone. No invitations are sent.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { confirm() }
                        .labelStyle(.iconOnly)
                }
            }
            .alert("Could Not Schedule Meeting", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func confirm() {
        guard selection == .everyWeek else {
            dismiss()
            return
        }
        do {
            try MeetingRepeatService.scheduleNextOccurrence(of: meeting, context: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
