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

/// Opens the one-sheet "Send Minutes" flow (preview, format, recipients, Send) and shows the outcome.
/// Mail can confirm `.sent`; a generic activity can only confirm shared/exported completion.
///
/// Every route that hands minutes to the system (Share button, toolbar share, PDF preview, Export) must end in a
/// success screen only when the system reports completion. The success screen is presented with `fullScreenCover`,
/// not with a push, because the Meetings tab uses a path-bound NavigationStack and a pushed `isPresented`
/// destination is dropped when the path is rewritten. The cover is shown from the dismissal callback of the Send
/// sheet, with a timed fallback, because UIKit may report completion before or after SwiftUI sees the sheet go away.
/// Cancelled, saved and failed Mail results never leave the Send sheet and never show success.
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

    @State private var showSend = false
    @State private var showActivity = false
    @State private var showSent = false
    @State private var pendingSent = false
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var activityFile: URL?
    @State private var sentState: MinutesSentState?

    private var candidates: [Speaker] {
        MinutesSendPlan.candidates(from: meeting?.namedAttendees ?? [], userName: userName)
    }

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
            .sheet(isPresented: $showSend, onDismiss: presentSentIfPending) {
                MinutesSendSheet(candidates: candidates, meeting: meeting, formats: formats, subject: subject,
                                 prepare: { format in try makePackage(format: format) },
                                 onCompleted: { outcome, people, package in
                    completeFromSheet(outcome, people: people, package: package)
                })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
                        MinutesSentView(state: sentState, meeting: meeting) {
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
        showSend = true
    }

    private func beginExternal(_ request: MinutesShareRequest) {
        subject = viewModel.headerTitle
        bodyText = request.text
        activityFile = request.fileURL
        showActivity = true
    }

    /// Builds the text and PDF for a format. A format that cannot be produced shows its message in the Send sheet.
    private func makePackage(format: MinutesShareFormat) throws -> MinutesSharePackage {
        let fileName = MinutesShareAttachment.safeName(subject)
        switch format {
        case .minutes:
            let text = shareText?() ?? viewModel.exportPlainText()
            let data = try viewModel.exportPDF()
            guard data.starts(with: Data("%PDF-".utf8)) else { throw MinutesShareFormatError.notAPDF }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Manent-Minutes-\(UUID().uuidString).pdf")
            try data.write(to: url, options: .atomic)
            let attachment = MinutesShareAttachment(data: data, fileName: "\(fileName) - Minutes.pdf")
            return MinutesSharePackage(bodyText: text, attachment: attachment, fileURL: url)
        case .formal:
            guard let formalText, let formalPDF else { throw MinutesShareFormatError.unavailable }
            let url = try formalPDF()
            let attachment = MinutesShareAttachment(data: try Data(contentsOf: url), fileName: "\(fileName) - Formal MoM.pdf")
            return MinutesSharePackage(bodyText: formalText(), attachment: attachment, fileURL: url)
        }
    }

    /// Called by the Send sheet only for Mail `.sent` or a completed share activity.
    private func completeFromSheet(_ outcome: MinutesShareOutcome, people: [Speaker], package: MinutesSharePackage) {
        guard let channel = outcome.recordedChannel else { return }
        bodyText = package.bodyText
        finish(channel: channel, outcome: outcome, people: people)
        showSend = false
    }

    /// Result of the external share sheet (PDF preview, Export). Cancelled and failed attempts show no success screen.
    private func handle(_ outcome: MinutesShareOutcome) {
        if let message = outcome.errorMessage {
            onError(message)
            return
        }
        guard let channel = outcome.recordedChannel else { return }
        finish(channel: channel, outcome: outcome, people: [])
    }

    private func finish(channel: SharedMinutesEntry.Channel, outcome: MinutesShareOutcome, people: [Speaker]) {
        guard let meeting else { return }
        let recipients: [SharedMinutesRecipient] = channel == .mail
            ? people.map { SharedMinutesRecipient(name: $0.name, email: $0.email, colorHex: $0.avatarColorHex) }
            : []
        let entry = SharedMinutesEntry(channel: channel, recipients: recipients, subject: subject, bodyText: bodyText)
        do {
            try MeetingRecordStore.shared.update(meeting.id) { $0.shares.append(entry) }
        } catch {
            onError(error.localizedDescription)
        }
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
        guard pendingSent, sentState != nil, !showSend, !showActivity else { return }
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

    /// Segmented-control label.
    var shortTitle: String {
        switch self {
        case .minutes: return "Minutes"
        case .formal: return "Formal MoM"
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
