import SwiftUI
import PDFKit
import MessageUI
import UIKit

/// The PDF and message text that go out together for one format.
struct MinutesSharePackage: Equatable {
    let bodyText: String
    let attachment: MinutesShareAttachment
    let fileURL: URL
}

/// "Send Minutes": one sheet with the PDF preview, the format, the recipients and a pinned Send button.
///
/// Mail and the share sheet are presented from this sheet, so a cancelled, saved or failed attempt returns here
/// with an honest note. Only Mail's `.sent` and a completed share activity are reported through `onCompleted`.
struct MinutesSendSheet: View {
    let candidates: [Speaker]
    let meeting: Meeting?
    let formats: [MinutesShareFormat]
    let subject: String
    let prepare: @MainActor (MinutesShareFormat) throws -> MinutesSharePackage
    let onCompleted: (MinutesShareOutcome, [Speaker], MinutesSharePackage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID>
    @State private var format: MinutesShareFormat = .minutes
    @State private var packages: [MinutesShareFormat: MinutesSharePackage] = [:]
    @State private var prepareError: String?
    @State private var thumbnail: UIImage?
    @State private var pageCount = 0
    @State private var notice: String?
    @State private var showMail = false
    @State private var showActivity = false
    @State private var showPreview = false
    @State private var showAddPerson = false

    private let mailAvailable = MFMailComposeViewController.canSendMail()

    init(candidates: [Speaker], meeting: Meeting?, formats: [MinutesShareFormat], subject: String,
         prepare: @escaping @MainActor (MinutesShareFormat) throws -> MinutesSharePackage,
         onCompleted: @escaping (MinutesShareOutcome, [Speaker], MinutesSharePackage) -> Void) {
        self.candidates = candidates
        self.meeting = meeting
        self.formats = formats
        self.subject = subject
        self.prepare = prepare
        self.onCompleted = onCompleted
        _selectedIDs = State(initialValue: MinutesSendPlan.defaultSelection(candidates))
    }

    private var package: MinutesSharePackage? { packages[format] }
    private var chosen: [Speaker] { candidates.filter { selectedIDs.contains($0.id) } }

    private var disabledReason: String? {
        MinutesSendPlan.disabledReason(candidateCount: candidates.count, selectedCount: chosen.count,
                                       isPreparing: package == nil && prepareError == nil,
                                       mailAvailable: mailAvailable)
    }

    private var canSend: Bool { package != nil && disabledReason == nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewCard
                    if formats.count > 1 { formatPicker }
                    noticeBanner
                    recipientsSection
                    shareAnotherWay
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Send Minutes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { sendBar }
            .onChange(of: candidates.map { $0.id }) { old, new in
                // Someone added from this sheet is selected right away.
                selectedIDs.formUnion(Set(new).subtracting(old))
            }
            .task(id: format) { @MainActor in await loadPackage() }
            .task(id: package?.fileURL) { @MainActor in await loadThumbnail() }
            .sheet(isPresented: $showMail) {
                RecordMailComposer(recipients: chosen.compactMap { $0.email }, subject: subject,
                                   bodyText: package?.bodyText ?? "", attachment: package?.attachment) { result, error in
                    showMail = false
                    mailFinished(MinutesShareOutcome.fromMail(result, error: error))
                }
            }
            .sheet(isPresented: $showActivity) {
                RecordActivitySheet(text: package?.bodyText ?? "", fileURL: package?.fileURL) { completed in
                    showActivity = false
                    activityFinished(completed)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showAddPerson) {
                if let meeting {
                    MeetingAddPersonSheet(meeting: meeting)
                        .presentationDragIndicator(.visible)
                }
            }
            .fullScreenCover(isPresented: $showPreview) {
                if let package {
                    MinutesPDFFullScreenView(url: package.fileURL, title: package.attachment.fileName,
                                             pageCount: pageCount)
                }
            }
        }
    }

    // MARK: - Preview

    private var previewCard: some View {
        Button {
            if package != nil { showPreview = true }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(8)
                    } else if let prepareError {
                        Label(prepareError, systemImage: "doc.badge.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(16)
                    } else {
                        ProgressView()
                    }
                }
                .frame(height: 220)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                Label(previewCaption, systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.Colors.manentAccent)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(package == nil)
        .accessibilityLabel(previewAccessibilityLabel)
        .accessibilityHint("Opens the full-screen preview")
    }

    private var previewCaption: String {
        pageCount > 0 ? "\(pageCountText) \u{00B7} Tap to preview" : "Tap to preview"
    }

    private var pageCountText: String { pageCount == 1 ? "1 page" : "\(pageCount) pages" }

    private var previewAccessibilityLabel: String {
        pageCount > 0 ? "Preview PDF, \(pageCountText)" : "Preview PDF"
    }

    private var formatPicker: some View {
        Picker("Format", selection: $format) {
            ForEach(formats) { option in
                Text(option.shortTitle).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Format")
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice {
            Label(notice, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.warmAmber.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Recipients

    private var recipientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attendees")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { entry in
                    recipientRow(entry.element)
                    if entry.offset < candidates.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
                if meeting != nil {
                    if !candidates.isEmpty { Divider().padding(.leading, 16) }
                    Button {
                        showAddPerson = true
                    } label: {
                        Label("Add someone", systemImage: "plus")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.manentAccent)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .padding(.horizontal, 16)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Add a person with an email address to this meeting")
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func recipientRow(_ person: Speaker) -> some View {
        let isSelected = selectedIDs.contains(person.id)
        return Button {
            if isSelected { selectedIDs.remove(person.id) } else { selectedIDs.insert(person.id) }
        } label: {
            HStack(spacing: 12) {
                Text(MeetingRecordInitials.initials(person.name))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color(hex: person.avatarColorHex), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name).font(.body).foregroundStyle(.primary)
                    Text(person.email ?? "").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark" : "circle")
                    .font(isSelected ? .body.weight(.semibold) : .body)
                    .foregroundStyle(isSelected ? Theme.Colors.manentAccent : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
    }

    private var shareAnotherWay: some View {
        Button {
            notice = nil
            showActivity = true
        } label: {
            Label("Share another way", systemImage: "square.and.arrow.up")
                .font(.body)
                .foregroundStyle(Theme.Colors.manentAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(package == nil)
        .accessibilityHint("Share the PDF with WhatsApp, AirDrop or another app")
    }

    // MARK: - Send bar

    private var sendBar: some View {
        VStack(spacing: 8) {
            if let reason = disabledReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if !mailAvailable {
                Text("Mail is not set up on this iPhone, so the PDF goes through the share sheet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: send) {
                Text(MinutesSendPlan.buttonTitle(count: chosen.count, mailAvailable: mailAvailable))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.Colors.manentAccent.opacity(canSend ? 1 : 0.35), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(MinutesSendPlan.accessibilityLabel(count: chosen.count, mailAvailable: mailAvailable))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Behaviour

    @MainActor
    private func loadPackage() async {
        if packages[format] != nil { return }
        prepareError = nil
        thumbnail = nil
        pageCount = 0
        await Task.yield()
        do {
            packages[format] = try prepare(format)
        } catch {
            prepareError = error.localizedDescription
        }
    }

    @MainActor
    private func loadThumbnail() async {
        guard let url = package?.fileURL else { return }
        let result = await Task.detached(priority: .userInitiated) { () -> (UIImage?, Int) in
            guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return (nil, 0) }
            let image = page.thumbnail(of: CGSize(width: 520, height: 736), for: .mediaBox)
            return (image, document.pageCount)
        }.value
        if Task.isCancelled { return }
        thumbnail = result.0
        pageCount = result.1
    }

    private func send() {
        guard canSend else { return }
        notice = nil
        if mailAvailable { showMail = true } else { showActivity = true }
    }

    private func mailFinished(_ outcome: MinutesShareOutcome) {
        if outcome.recordedChannel != nil, let package {
            onCompleted(outcome, chosen, package)
        } else {
            notice = outcome.sendSheetNotice(viaMail: true)
        }
    }

    private func activityFinished(_ completed: Bool) {
        let outcome = MinutesShareOutcome.fromActivity(completed: completed)
        if outcome.recordedChannel != nil, let package {
            onCompleted(outcome, [], package)
        } else {
            notice = outcome.sendSheetNotice(viaMail: false)
        }
    }
}

/// Full-screen PDF preview with pinch zoom, the page count, Share and Print.
struct MinutesPDFFullScreenView: View {
    let url: URL
    let title: String
    let pageCount: Int

    @Environment(\.dismiss) private var dismiss

    private var subtitle: String { pageCount == 1 ? "1 page" : "\(pageCount) pages" }

    var body: some View {
        NavigationStack {
            MoMPDFKitView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text(title).font(.headline).lineLimit(1)
                            if pageCount > 0 {
                                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Print", systemImage: "printer") { printPDF() }
                            .labelStyle(.iconOnly)
                        ShareLink(item: url)
                    }
                }
        }
        .tint(Theme.Colors.manentAccent)
    }

    private func printPDF() {
        guard UIPrintInteractionController.canPrint(url) else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = title
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true)
    }
}
