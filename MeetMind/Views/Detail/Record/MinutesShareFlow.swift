import SwiftUI
import MessageUI
import UIKit

/// Something other than the plain minutes text to hand over, for example the PDF opened from the preview.
/// It always goes through the same share-sheet path as the Share button, so it reaches the outcome screens.
struct MinutesShareRequest: Identifiable, Equatable {
    let id = UUID()
    var fileURL: URL
    var text: String
}

/// Choose recipients, confirm, hand the minutes to Mail or the share sheet, then show the confirmed outcome.
/// Mail can confirm `.sent`; a generic activity can only confirm shared/exported completion.
///
/// Every route that hands minutes to the system (Share button, toolbar share, PDF preview, Export) must end in
/// `handle(_:)`. The outcome screens (animated B9, settled B10) are presented with `fullScreenCover`, not with a
/// push, because the Meetings tab uses a path-bound NavigationStack and a pushed `isPresented` destination is
/// dropped when the path is rewritten. The cover is shown from the dismissal callback of the Mail or share sheet,
/// with a timed fallback, because UIKit may report completion before or after SwiftUI sees the sheet go away.
@MainActor
struct MinutesShareFlowModifier: ViewModifier {
    let meeting: Meeting?
    let viewModel: MeetingDetailViewModel
    let userName: String?
    @Binding var isStarting: Bool
    @Binding var externalRequest: MinutesShareRequest?
    let onBackToMeetings: () -> Void
    let onError: (String) -> Void
    /// Text handed to Mail and the share sheet for the "Minutes" format. Defaults to the plain-text export.
    var shareText: (() -> String)? = nil
    /// Text and PDF for the "Formal MoM" format. When either is nil the Format row is hidden.
    var formalText: (() -> String)? = nil
    var formalPDF: (() throws -> URL)? = nil

    @State private var showRecipients = false
    @State private var proceedToConfirm = false
    @State private var showConfirm = false
    @State private var showMail = false
    @State private var showActivity = false
    @State private var showSent = false
    @State private var pendingSent = false
    @State private var selectedIDs = Set<UUID>()
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var activityFile: URL?
    @State private var sentState: MinutesSentState?
    @State private var sentEntry: SharedMinutesEntry?
    @State private var format: MinutesShareFormat = .minutes
    @State private var attachment: MinutesShareAttachment?

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

    private var formats: [MinutesShareFormat] {
        formalText != nil && formalPDF != nil ? MinutesShareFormat.allCases : [.minutes]
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: isStarting) { _, starting in
                if starting {
                    isStarting = false
                    begin()
                }
            }
            .onChange(of: externalRequest) { _, request in
                guard let request else { return }
                externalRequest = nil
                beginExternal(request)
            }
            .sheet(isPresented: $showRecipients, onDismiss: {
                if proceedToConfirm {
                    proceedToConfirm = false
                    showConfirm = true
                }
            }) {
                MinutesRecipientsSheet(people: candidates, selectedIDs: $selectedIDs, format: $format,
                                       formats: formats, meeting: meeting) {
                    proceedToConfirm = true
                    showRecipients = false
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .alert("Send Minutes to \(countLabel)?", isPresented: $showConfirm) {
                Button("Send to \(countLabel)") { deliver() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(MeetingRecordFormatting.joinedNames(chosen.map { MeetingRecordFormatting.firstName($0.name) })
                     + " get the minutes and their action items.")
            }
            .sheet(isPresented: $showMail, onDismiss: presentSentIfPending) {
                RecordMailComposer(recipients: chosen.compactMap(\.email), subject: subject, bodyText: bodyText,
                                   attachment: attachment) { result, error in
                    showMail = false
                    handle(MinutesShareOutcome.fromMail(result, error: error))
                }
            }
            .sheet(isPresented: $showActivity, onDismiss: presentSentIfPending) {
                RecordActivitySheet(text: bodyText, fileURL: activityFile) { completed in
                    showActivity = false
                    handle(MinutesShareOutcome.fromActivity(completed: completed))
                }
                .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $showSent, onDismiss: { sentState = nil }) {
                NavigationStack {
                    if let sentState {
                        MinutesSentView(state: sentState, entry: sentEntry, meeting: meeting) {
                            showSent = false
                            onBackToMeetings()
                        }
                    }
                }
                .tint(Theme.Colors.manentAccent)
            }
    }

    private func begin() {
        subject = viewModel.headerTitle
        bodyText = shareText?() ?? viewModel.exportPlainText()
        activityFile = nil
        attachment = nil
        format = .minutes
        if candidates.isEmpty {
            selectedIDs = []
            showActivity = true
        } else {
            selectedIDs = Set(candidates.map(\.id))
            showRecipients = true
        }
    }

    private func beginExternal(_ request: MinutesShareRequest) {
        subject = viewModel.headerTitle
        bodyText = request.text
        activityFile = request.fileURL
        attachment = nil
        selectedIDs = []
        showActivity = true
    }

    /// Builds the text and PDF for the chosen format. A format that cannot be produced stops the send with a message.
    private func prepareFormat() throws {
        let fileName = MinutesShareAttachment.safeName(subject)
        switch format {
        case .minutes:
            bodyText = shareText?() ?? viewModel.exportPlainText()
            let data = try viewModel.exportPDF()
            guard data.starts(with: Data("%PDF-".utf8)) else { throw MinutesShareFormatError.notAPDF }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Manent-Minutes-\(UUID().uuidString).pdf")
            try data.write(to: url, options: .atomic)
            attachment = MinutesShareAttachment(data: data, fileName: "\(fileName) - Minutes.pdf")
            activityFile = url
        case .formal:
            guard let formalText, let formalPDF else { throw MinutesShareFormatError.unavailable }
            bodyText = formalText()
            let url = try formalPDF()
            attachment = MinutesShareAttachment(data: try Data(contentsOf: url), fileName: "\(fileName) - Formal MoM.pdf")
            activityFile = url
        }
    }

    private func deliver() {
        do {
            try prepareFormat()
        } catch {
            onError(error.localizedDescription)
            return
        }
        let useMail = MFMailComposeViewController.canSendMail()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if useMail { showMail = true } else { showActivity = true }
        }
    }

    /// Cancelled, saved-as-draft and failed attempts record nothing and show no success screen.
    private func handle(_ outcome: MinutesShareOutcome) {
        if let message = outcome.errorMessage {
            onError(message)
            return
        }
        guard let channel = outcome.recordedChannel else { return }
        finish(channel: channel, outcome: outcome)
    }

    private func finish(channel: SharedMinutesEntry.Channel, outcome: MinutesShareOutcome) {
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
        sentEntry = entry
        sentState = MinutesSentState.make(outcome: outcome, recipients: recipients)
        pendingSent = sentState != nil
        // The sheet's dismissal callback normally presents the cover. This covers the case where the
        // completion callback arrives after SwiftUI already finished dismissing the sheet.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            presentSentIfPending()
        }
    }

    private func presentSentIfPending() {
        guard pendingSent, sentState != nil, !showMail, !showActivity else { return }
        pendingSent = false
        showSent = true
    }
}

/// What the minutes are sent as. Both formats go out as a PDF with the matching text in the message.
enum MinutesShareFormat: String, CaseIterable, Identifiable {
    case minutes
    case formal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minutes: return "Minutes \u{00B7} PDF"
        case .formal: return "Formal MoM \u{00B7} PDF"
        }
    }
}

/// A PDF attached to the Mail message.
struct MinutesShareAttachment: Equatable {
    let data: Data
    let fileName: String

    /// A file-name-safe version of the meeting title.
    static func safeName(_ title: String) -> String {
        let blocked = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = title.components(separatedBy: blocked).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Meeting" : cleaned
    }
}

enum MinutesShareFormatError: LocalizedError {
    case notAPDF
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notAPDF: return "The generated file is not a PDF document."
        case .unavailable: return "The formal minutes are not available for this meeting."
        }
    }
}

/// "Send Minutes To": a Format row, the attendees with an email address and a check on the right, and Add Someone.
/// The top-right check continues.
struct MinutesRecipientsSheet: View {
    let people: [Speaker]
    @Binding var selectedIDs: Set<UUID>
    @Binding var format: MinutesShareFormat
    let formats: [MinutesShareFormat]
    let meeting: Meeting?
    let onConfirm: () -> Void
    @State private var showAddPerson = false

    var body: some View {
        NavigationStack {
            List {
                if formats.count > 1 {
                    Section {
                        Picker("Format", selection: $format) {
                            ForEach(formats) { option in Text(option.title).tag(option) }
                        }
                        .pickerStyle(.menu)
                        .frame(minHeight: 44)
                    }
                }
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
                                Image(systemName: selectedIDs.contains(person.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedIDs.contains(person.id) ? Theme.Colors.manentAccent : Color.secondary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(selectedIDs.contains(person.id) ? "Selected" : "Not selected")
                    }
                    if meeting != nil {
                        Button {
                            showAddPerson = true
                        } label: {
                            Label("Add someone", systemImage: "plus.circle.fill")
                                .foregroundStyle(Theme.Colors.manentAccent)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityHint("Add a person with an email address to this meeting")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Send Minutes To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", systemImage: "checkmark", action: onConfirm)
                        .labelStyle(.iconOnly)
                        .toolbarConfirmButtonStyle()
                        .disabled(selectedIDs.isEmpty)
                }
            }
            .onChange(of: people.map { $0.id }) { old, new in
                // Someone added from this sheet is selected right away.
                selectedIDs.formUnion(Set(new).subtracting(old))
            }
            .sheet(isPresented: $showAddPerson) {
                if let meeting {
                    MeetingAddPersonSheet(meeting: meeting)
                        .presentationDragIndicator(.visible)
                }
            }
        }
    }
}
struct RecordMailComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let bodyText: String
    var attachment: MinutesShareAttachment? = nil
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
        if let attachment {
            controller.addAttachmentData(attachment.data, mimeType: "application/pdf", fileName: attachment.fileName)
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}
}

/// System share sheet. `completion(true)` means the user finished an activity (sent, saved or copied).
struct RecordActivitySheet: UIViewControllerRepresentable {
    let text: String
    var fileURL: URL?
    let completion: (Bool) -> Void

    private var items: [Any] {
        if let fileURL { return [fileURL] }
        return [text]
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let completion = self.completion
        controller.completionWithItemsHandler = { _, completed, _, _ in
            completion(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
