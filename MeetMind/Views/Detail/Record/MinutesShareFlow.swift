import SwiftUI
import MessageUI
import UIKit

/// Choose recipients, confirm, hand the minutes to Mail or the share sheet, then show "Minutes Sent".
/// The user sends the message. Manent only records that the user did so (`MeetingRecordStore`).
@MainActor
struct MinutesShareFlowModifier: ViewModifier {
    let meeting: Meeting?
    let viewModel: MeetingDetailViewModel
    let userName: String?
    @Binding var isStarting: Bool
    let onBackToMeetings: () -> Void
    let onError: (String) -> Void

    @State private var showRecipients = false
    @State private var proceedToConfirm = false
    @State private var showConfirm = false
    @State private var showMail = false
    @State private var showActivity = false
    @State private var showSent = false
    @State private var selectedIDs = Set<UUID>()
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var sentRecipients: [SharedMinutesRecipient] = []
    @State private var sentMessage = ""

    private var candidates: [Speaker] {
        var seen = Set<String>()
        return (meeting?.namedAttendees ?? []).filter { person in
            guard person.name != userName,
                  let email = person.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !email.isEmpty else { return false }
            return seen.insert(email).inserted
        }
    }

    private var chosen: [Speaker] { candidates.filter { selectedIDs.contains($0.id) } }

    private var countLabel: String { chosen.count == 1 ? "1 Person" : "\(chosen.count) People" }

    func body(content: Content) -> some View {
        content
            .onChange(of: isStarting) { _, starting in
                if starting {
                    isStarting = false
                    begin()
                }
            }
            .sheet(isPresented: $showRecipients, onDismiss: {
                if proceedToConfirm {
                    proceedToConfirm = false
                    showConfirm = true
                }
            }) {
                MinutesRecipientsSheet(people: candidates, selectedIDs: $selectedIDs) {
                    proceedToConfirm = true
                    showRecipients = false
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog("Send Minutes to \(countLabel)?", isPresented: $showConfirm, titleVisibility: .visible) {
                Button("Send to \(countLabel)") { deliver() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(MeetingRecordFormatting.joinedNames(chosen.map { MeetingRecordFormatting.firstName($0.name) })
                     + " get the minutes and their action items.")
            }
            .sheet(isPresented: $showMail) {
                RecordMailComposer(recipients: chosen.compactMap(\.email), subject: subject, bodyText: bodyText) { result, error in
                    showMail = false
                    if let error {
                        onError(error.localizedDescription)
                    } else if result == .sent {
                        finish(channel: .mail)
                    }
                }
            }
            .sheet(isPresented: $showActivity) {
                RecordActivitySheet(text: bodyText) { completed in
                    showActivity = false
                    if completed { finish(channel: .shareSheet) }
                }
                .presentationDetents([.medium, .large])
            }
            .navigationDestination(isPresented: $showSent) {
                MinutesSentView(recipients: sentRecipients, message: sentMessage, meeting: meeting,
                                onBackToMeetings: onBackToMeetings)
                    .toolbar(.hidden, for: .tabBar)
            }
    }

    private func begin() {
        subject = viewModel.headerTitle
        bodyText = viewModel.exportPlainText()
        if candidates.isEmpty {
            selectedIDs = []
            showActivity = true
        } else {
            selectedIDs = Set(candidates.map(\.id))
            showRecipients = true
        }
    }

    private func deliver() {
        let useMail = MFMailComposeViewController.canSendMail()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if useMail { showMail = true } else { showActivity = true }
        }
    }

    private func finish(channel: SharedMinutesEntry.Channel) {
        guard let meeting else { return }
        let recipients: [SharedMinutesRecipient] = channel == .mail
            ? chosen.map { SharedMinutesRecipient(name: $0.name, email: $0.email, colorHex: $0.avatarColorHex) }
            : []
        let entry = SharedMinutesEntry(channel: channel, recipients: recipients, subject: subject, bodyText: bodyText)
        do {
            try MeetingRecordStore.shared.update(meeting.id) { $0.shares.append(entry) }
        } catch {
            onError(error.localizedDescription)
        }
        sentRecipients = recipients
        if recipients.isEmpty {
            sentMessage = "The minutes were shared from this iPhone."
        } else {
            let names = MeetingRecordFormatting.joinedNames(recipients.map { MeetingRecordFormatting.firstName($0.name) })
            sentMessage = "\(names) \(recipients.count == 1 ? "has" : "have") the minutes and their action items."
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            showSent = true
        }
    }
}

/// "Send Minutes To": attendees with an email address and a check on the right. The top-right check continues.
struct MinutesRecipientsSheet: View {
    let people: [Speaker]
    @Binding var selectedIDs: Set<UUID>
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Attendees") {
                    ForEach(people, id: \.id) { person in
                        Button {
                            if selectedIDs.contains(person.id) {
                                selectedIDs.remove(person.id)
                            } else {
                                selectedIDs.insert(person.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name).foregroundStyle(.primary)
                                    Text(person.email ?? "")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedIDs.contains(person.id) {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.Colors.manentAccent)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(selectedIDs.contains(person.id) ? "Selected" : "Not selected")
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Send Minutes To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", systemImage: "checkmark", action: onConfirm)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }
}

struct RecordMailComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let bodyText: String
    let finished: (MFMailComposeResult, Error?) -> Void

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let finished: (MFMailComposeResult, Error?) -> Void
        init(finished: @escaping (MFMailComposeResult, Error?) -> Void) { self.finished = finished }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            finished(result, error)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(bodyText, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}
}

/// System share sheet. `completion(true)` means the user finished an activity (sent, saved or copied).
struct RecordActivitySheet: UIViewControllerRepresentable {
    let text: String
    let completion: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        let completion = self.completion
        controller.completionWithItemsHandler = { _, completed, _, _ in
            completion(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
