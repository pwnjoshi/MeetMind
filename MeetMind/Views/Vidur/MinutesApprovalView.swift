import SwiftUI
import MessageUI
import UIKit

/// Local adaptation of "Send for Approval". The user picks a reviewer from the meeting's participants,
/// checks the review list, and sends the minutes text themselves (Mail or the share sheet).
/// Manent keeps a record of who it was sent to and when. It never learns whether the reviewer approved.
@MainActor
public struct MinutesApprovalView: View {
    public let meeting: Meeting

    @Environment(\.dismiss) private var dismiss
    @State private var store = MinutesApprovalStore.shared
    @State private var reviewerID: UUID?
    @State private var showsMail = false
    @State private var showsShare = false
    @State private var showsReviewAlert = false
    @State private var showsSentAlert = false
    @State private var sentReviewerName = ""
    @State private var pendingText = ""
    @State private var pendingChannel: MinutesApprovalRecord.Channel = .shareSheet

    public init(meeting: Meeting) {
        self.meeting = meeting
    }

    private var checklist: ApprovalChecklist {
        ApprovalChecklist.evaluate(ApprovalChecklistInput.make(from: meeting))
    }

    private var reviewer: Speaker? {
        meeting.participants.first { $0.id == reviewerID }
    }

    private var records: [MinutesApprovalRecord] {
        store.records(for: meeting.id)
    }

    public var body: some View {
        List {
            Section {
                reviewerRow
            } header: {
                Text("Submit this exact reviewed version.")
                    .textCase(nil).font(.subheadline)
            }

            Section("Review Checklist") {
                ForEach(checklist.checks) { check in
                    HStack(alignment: .top, spacing: Spacing.md) {
                        Image(systemName: check.passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(check.passed ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.title)
                            Text(check.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if checklist.requiresReview {
                    Label("Requires review before it can be sent.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }

            if !records.isEmpty {
                Section {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sent by you to \(record.reviewerName)")
                            Text("\(record.sentAt.formatted(date: .abbreviated, time: .shortened)) \u{00B7} \(record.channel == .mail ? "Mail" : "Share sheet") \u{00B7} version \(record.versionTag)")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Approval Submitted")
                } footer: {
                    Text("These minutes stay unapproved until the reviewer responds. Manent does not track replies.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Send for Approval")
        .navigationBarTitleDisplayMode(.large)
        .tint(Theme.Colors.manentAccent)
        .safeAreaInset(edge: .bottom) { submitButton }
        .onAppear {
            if reviewerID == nil { reviewerID = meeting.participants.first?.id }
        }
        .sheet(isPresented: $showsMail) {
            MailComposeView(
                subject: "Minutes for review: \(meeting.title)",
                body: pendingText,
                recipients: reviewer?.email.map { [$0] } ?? []
            ) { sent in
                showsMail = false
                if sent { recordSent() }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsShare) {
            ActivityShareSheet(items: [pendingText]) { completed in
                showsShare = false
                if completed { recordSent() }
            }
            .ignoresSafeArea()
        }
        .alert("Finalize Minutes First", isPresented: $showsReviewAlert) {
            Button("Return to Meeting") { dismiss() }
        } message: {
            Text(reviewMessage)
        }
        .alert("Sent by You", isPresented: $showsSentAlert) {
            Button("Return to Meeting") { dismiss() }
            Button("Close", role: .cancel) {}
        } message: {
            Text("You sent these minutes to \(sentReviewerName). They stay unapproved until the reviewer responds. Manent does not track replies.")
        }
    }

    private var reviewMessage: String {
        let items = checklist.failedChecks.map { "\u{2022} \($0.title): \($0.detail)" }
        return "Review these items before submitting a version for approval.\n" + items.joined(separator: "\n")
    }

    @ViewBuilder
    private var reviewerRow: some View {
        if meeting.participants.isEmpty {
            HStack {
                Text("Approver")
                Spacer()
                Text("No participants saved").foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Text("Approver")
                Spacer()
                Picker("Approver", selection: $reviewerID) {
                    ForEach(meeting.participants) { person in
                        Text(person.name).tag(Optional(person.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            HStack {
                Text("Version")
                Spacer()
                Text(checklist.requiresReview ? "Needs review" : "Finalized").foregroundStyle(.secondary)
            }
        }
    }

    private var submitTitle: String {
        guard let reviewer else { return "Choose an Approver" }
        let first = reviewer.name.split(separator: " ").first.map(String.init) ?? reviewer.name
        return "Send to \(first)"
    }

    private var submitButton: some View {
        Button(action: submit) {
            Text(submitTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(Theme.Colors.manentAccent.opacity(reviewer == nil ? 0.4 : 1), in: Capsule())
        }
        .disabled(reviewer == nil)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }

    private func submit() {
        guard reviewer != nil else { return }
        guard !checklist.requiresReview else {
            showsReviewAlert = true
            return
        }
        pendingText = MinutesApprovalText.build(ApprovalMinutesInput.make(from: meeting))
        if MFMailComposeViewController.canSendMail() {
            pendingChannel = .mail
            showsMail = true
        } else {
            pendingChannel = .shareSheet
            showsShare = true
        }
    }

    private func recordSent() {
        guard let reviewer else { return }
        store.add(MinutesApprovalRecord(
            meetingID: meeting.id, reviewerName: reviewer.name, reviewerEmail: reviewer.email,
            channel: pendingChannel, versionTag: MinutesApprovalText.versionTag(for: pendingText)))
        sentReviewerName = reviewer.name
        showsSentAlert = true
    }
}

// MARK: - Mail composer

struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let recipients: [String]
    /// Called once with `true` only if the user actually sent the message.
    let onFinish: @MainActor (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        controller.setToRecipients(recipients)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: @MainActor (Bool) -> Void

        init(onFinish: @escaping @MainActor (Bool) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            let sent = result == .sent
            let callback = onFinish
            Task { @MainActor in callback(sent) }
        }
    }
}

// MARK: - Share sheet with completion

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [String]
    /// Called with `true` only if the user completed an activity (not when cancelled).
    let onFinish: @MainActor (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let callback = onFinish
        controller.completionWithItemsHandler = { _, completed, _, _ in
            Task { @MainActor in callback(completed) }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
