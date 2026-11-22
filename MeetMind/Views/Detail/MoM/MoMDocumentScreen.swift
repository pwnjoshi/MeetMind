import SwiftUI
import SwiftData

/// The Minutes of Meeting document (Figma B6 / B6c). It renders `MoMDocumentModel`, which is rebuilt from the live
/// meeting, `MeetingRecordStore` and `MoMSidecarStore` on every change, so edits made anywhere appear here at once.
@MainActor
struct MoMDocumentScreen: View {
    let meeting: Meeting
    let viewModel: MeetingDetailViewModel
    let isFinalized: Bool
    let userName: String?
    let onRename: () -> Void
    let onEdit: () -> Void
    let onOpenMeeting: (UUID) -> Void
    let onScheduleNext: () -> Void
    let onOpenStudio: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.createdAt) private var allMeetings: [Meeting]
    @State private var sidecars = MoMSidecarStore.shared
    @State private var records = MeetingRecordStore.shared
    @State private var errorMessage: String?
    @State private var showSignature = false
    @State private var showSignHint = false
    @State private var selectedPerson: Speaker?

    private var sidecar: MoMSidecar { sidecars.sidecar(for: meeting.id) }

    private var document: MoMDocumentModel {
        let series = MoMDocumentBuilder.seriesMeetings(of: meeting, in: allMeetings)
        let provisional = sidecar.referenceNumber ?? MoMReference.format(
            title: meeting.seriesName ?? meeting.title,
            year: Calendar(identifier: .gregorian).component(.year, from: meeting.scheduledStartTime ?? meeting.createdAt),
            sequence: 1)
        return MoMDocumentBuilder.build(
            meeting: meeting, record: records.record(for: meeting.id), sidecar: sidecar,
            reference: provisional, isFinalized: isFinalized, userName: userName,
            seriesMeetings: series, studioConfig: MinutesStudioStore.shared.config(for: meeting.id))
    }

    private var canPlay: Bool { meeting.resolvedAudioFileURL != nil }

    var body: some View {
        let doc = document
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(doc)
                    detailCard(doc)
                    chips(proxy)
                    attendance(doc).id("attendance")
                    previous(doc)
                    agenda(doc).id("agenda")
                    actions(doc).id("actions")
                    simpleSection("5. Any Other Business", doc.anyOtherBusiness)
                    nextMeeting(doc)
                    simpleSection("7. Closure", doc.closure.isEmpty ? "Not recorded." : doc.closure)
                    signOff(doc)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationDestination(item: $selectedPerson) { person in
            MoMPersonPage(person: person, meeting: meeting, onPlay: play)
        }
        .sheet(isPresented: $showSignature) {
            MoMSignatureSheet(signerName: doc.signOff.name, initialPlace: sidecar.signedPlace ?? "") { png, place in
                sign(png: png, place: place, name: doc.signOff.name)
            }
        }
        .alert("Finalize Before Signing", isPresented: $showSignHint) {
            Button("OK") {}
        } message: {
            Text("A signature covers the reviewed text. Review and finalize the minutes first.")
        }
        .recordErrorAlert("Could Not Update Minutes", message: $errorMessage)
        .task(id: meeting.id) { ensureReference() }
    }

    // MARK: Header

    private func header(_ doc: MoMDocumentModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MINUTES OF MEETING")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.Colors.manentAccent)
                Spacer()
                Text(doc.reference).font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Reference \(doc.reference)")
            }
            Button(action: onRename) {
                Text(doc.title).font(.largeTitle.bold()).multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Rename this meeting")
            if !doc.subtitle.isEmpty {
                Text(doc.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                MoMStatusPill(status: doc.status)
                formatMenu(doc)
            }
            .padding(.top, 4)
        }
        .padding(.top, 4)
    }

    private func formatMenu(_ doc: MoMDocumentModel) -> some View {
        let current = sidecar.style ?? .corporateIndia
        return Menu {
            ForEach(MoMStyle.allCases) { style in
                Button { setStyle(style) } label: {
                    if style == current {
                        Label(style.title, systemImage: "checkmark")
                    } else {
                        Text(style.title)
                    }
                    Text(style.subtitle)
                }
            }
            Divider()
            Button("Minutes Studio\u{2026}", action: onOpenStudio)
        } label: {
            HStack(spacing: 4) {
                Text(current.shortTitle)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.Colors.manentAccent)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.Colors.manentAccent.opacity(0.12), in: Capsule())
        }
        .accessibilityLabel("Format: \(current.shortTitle)")
    }

    private func detailCard(_ doc: MoMDocumentModel) -> some View {
        MoMCard {
            detailRow("Date", value: doc.dateText, icon: "calendar", tint: .red)
            Divider().padding(.leading, 56)
            detailRow("Time", value: doc.timeText, icon: "clock", tint: .indigo)
            Divider().padding(.leading, 56)
            Button(action: onEdit) {
                detailRow("Venue", value: doc.venue ?? "Add venue", icon: "location.fill", tint: .orange)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 56)
            Button(action: onEdit) {
                personDetailRow("Chairperson", value: doc.chairperson ?? "Not set", name: doc.chairperson)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 56)
            Button(action: onEdit) {
                personDetailRow("Minutes by", value: doc.minutesBy ?? "Not set", name: doc.minutesBy)
            }
            .buttonStyle(.plain)
        }
    }

    private func detailRow(_ label: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 32)
            Text(label).font(.body)
            Spacer(minLength: 8)
            Text(value).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func personDetailRow(_ label: String, value: String, name: String?) -> some View {
        HStack(spacing: 12) {
            if let name {
                MoMAvatar(initials: MeetingRecordInitials.initials(name), colorHex: colorHex(for: name))
            } else {
                Image(systemName: "person.crop.circle").font(.title2).foregroundStyle(.secondary).frame(width: 32)
            }
            Text(label).font(.body)
            Spacer(minLength: 8)
            Text(value).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func colorHex(for name: String) -> String {
        meeting.participants.first(where: { $0.name == name })?.avatarColorHex ?? "#4F46E5"
    }

    private func chips(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MoMDocumentModel.sectionTitles, id: \.id) { section in
                    Button(section.title) {
                        withAnimation { proxy.scrollTo(section.id == "decisions" ? decisionAnchor : section.id, anchor: .top) }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(section.id == "attendance" ? Color.white : Color.primary)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(section.id == "attendance" ? Theme.Colors.manentAccent : Color(uiColor: .tertiarySystemFill),
                                in: Capsule())
                    .accessibilityHint("Scrolls to \(section.title)")
                }
            }
        }
    }

    private var decisionAnchor: String {
        document.topics.first(where: { $0.outcomeKind == .resolved && $0.hasOutcome })?.id ?? "agenda"
    }

    // MARK: Sections

    private func attendance(_ doc: MoMDocumentModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MoMSectionTitle(text: "1. Attendance")
            if let quorum = doc.quorumText {
                Label(quorum, systemImage: doc.quorumMet ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(doc.quorumMet ? Color.green : Color.orange)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background((doc.quorumMet ? Color.green : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            if doc.present.isEmpty && doc.invitees.isEmpty && doc.leave.isEmpty {
                MoMCard { Text("No attendees yet. Add people from Edit Minutes.").font(.subheadline)
                    .foregroundStyle(.secondary).padding(16) }
            }
            personGroup("Present", doc.present)
            personGroup("In attendance (invitee)", doc.invitees)
            personGroup("Leave of absence", doc.leave)
            mentions(doc)
        }
    }

    @ViewBuilder
    private func personGroup(_ title: String, _ rows: [MoMDocumentModel.PersonRow]) -> some View {
        if !rows.isEmpty {
            MoMCaption(text: title)
            MoMCard {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().padding(.leading, 60) }
                    MoMPersonRowView(row: row) { open(row) }
                }
            }
        }
    }

    @ViewBuilder
    private func mentions(_ doc: MoMDocumentModel) -> some View {
        if !doc.mentionedPeople.isEmpty {
            MoMCaption(text: "People mentioned \u{2014} add?")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(doc.mentionedPeople) { person in
                        HStack(spacing: 0) {
                            Button { addMention(person.name) } label: {
                                Label(person.name, systemImage: "plus")
                                    .font(.footnote.weight(.semibold))
                                    .padding(.leading, 12).padding(.trailing, 8).frame(minHeight: 44)
                            }
                            Button { dismissMention(person.name) } label: {
                                Image(systemName: "xmark").font(.caption2.weight(.bold))
                                    .padding(.trailing, 12).frame(minHeight: 44)
                            }
                            .accessibilityLabel("Dismiss \(person.name)")
                        }
                        .foregroundStyle(Theme.Colors.manentAccent)
                        .background(Theme.Colors.manentAccent.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }

    private func previous(_ doc: MoMDocumentModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MoMSectionTitle(text: "2. Previous Minutes")
            MoMCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(doc.previous.text).font(.subheadline)
                    if let id = doc.previous.meetingID, let link = doc.previous.linkTitle {
                        Button(link) { onOpenMeeting(id) }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Colors.manentAccent)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                }
                .padding(16)
            }
        }
    }

    private func agenda(_ doc: MoMDocumentModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MoMSectionTitle(text: "3. Agenda and Discussion")
            if doc.topics.isEmpty {
                MoMCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No agenda topics were recorded.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Add Topics", action: onEdit).font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .padding(16)
                }
            }
            ForEach(Array(doc.topics.enumerated()), id: \.element.id) { index, topic in
                MoMTopicCard(number: "3.\(index + 1)", topic: topic, canPlay: canPlay, onPlay: play)
                    .id(topic.id)
            }
        }
    }

    private func actions(_ doc: MoMDocumentModel) -> some View {
        let content = MeetingMinutesContent.make(from: meeting, record: records.record(for: meeting.id))
        return VStack(alignment: .leading, spacing: 10) {
            MoMSectionTitle(text: "4. Action Taken Report")
            if doc.actions.isEmpty {
                MoMCard { Text("No actions were recorded.").font(.subheadline).foregroundStyle(.secondary).padding(16) }
            } else {
                MoMActionTable(rows: doc.actions, onToggle: toggle)
            }
            if !content.suggestions.isEmpty {
                MoMCaption(text: "Suggested \u{2014} review")
                MoMCard {
                    ForEach(Array(content.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        if index > 0 { Divider() }
                        SuggestedTaskRow(meeting: meeting, suggestion: suggestion).padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func simpleSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MoMSectionTitle(text: title)
            MoMCard { Text(text).font(.subheadline).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
        }
    }

    private func nextMeeting(_ doc: MoMDocumentModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MoMSectionTitle(text: "6. Next Meeting")
            MoMCard {
                HStack(spacing: 12) {
                    Image(systemName: "calendar").foregroundStyle(.red).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.nextMeetingText ?? "Not scheduled").font(.subheadline.weight(.semibold))
                        if let note = doc.nextMeetingNote {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(action: onScheduleNext) {
                        Text("Add").font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Colors.manentAccent)
                            .padding(.horizontal, 16).frame(minHeight: 44)
                            .background(Theme.Colors.manentAccent.opacity(0.12), in: Capsule())
                    }
                    .accessibilityLabel("Add next meeting to calendar")
                }
                .padding(16)
            }
        }
    }

    private func signOff(_ doc: MoMDocumentModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MoMSectionTitle(text: "8. Sign-off")
            MoMCard {
                VStack(alignment: .leading, spacing: 12) {
                    signatureArea(doc)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.signOff.name).font(.headline)
                            Text(doc.signOff.role).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Date of signing  \(doc.signOff.signedAt.map(MoMDocumentBuilder.longDate) ?? "\u{2014}")")
                            Text("Place  \(doc.signOff.place ?? "\u{2014}")")
                        }
                        .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text(doc.signOff.recordedBy).font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private func signatureArea(_ doc: MoMDocumentModel) -> some View {
        if doc.status == .signed, let data = doc.signOff.signaturePNG, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 90)
                .accessibilityLabel("Signature of \(doc.signOff.name)")
                .contextMenu {
                    Button("Remove Signature", systemImage: "trash", role: .destructive) { removeSignature() }
                }
        } else {
            Button {
                if isFinalized { showSignature = true } else { showSignHint = true }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "signature").font(.title2).foregroundStyle(.secondary)
                    Text("Sign as Chairperson").font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Colors.manentAccent)
                }
                .frame(maxWidth: .infinity, minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6])).foregroundStyle(.secondary))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Actions

    private func play(_ time: Double) {
        guard canPlay else { return }
        viewModel.seek(to: time)
        if !viewModel.isPlaying { viewModel.togglePlayPause() }
    }

    private func open(_ row: MoMDocumentModel.PersonRow) {
        selectedPerson = meeting.participants.first(where: { $0.id.uuidString == row.id })
    }

    private func setStyle(_ style: MoMStyle) {
        do {
            try MoMEditor.edit(meeting, context: context, store: sidecars, material: false) { $0.style = style }
            var config = MinutesStudioStore.shared.config(for: meeting.id) ?? MinutesStudioConfig.standard()
            config.meetingType = style.meetingType
            config.format = style.studioFormat
            MinutesStudioStore.shared.save(config, for: meeting.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggle(_ row: MoMDocumentModel.ActionRow) {
        guard let item = meeting.actionItems.first(where: { $0.id.uuidString == row.id }) else { return }
        do { try MeetingRecordEditor.setCompleted(item, !item.isCompleted, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func addMention(_ name: String) {
        do { try MoMEditor.addMention(name, meeting: meeting, context: context, store: sidecars) }
        catch { errorMessage = error.localizedDescription }
    }

    private func dismissMention(_ name: String) {
        do { try MoMEditor.dismissMention(name, meeting: meeting, store: sidecars) }
        catch { errorMessage = error.localizedDescription }
    }

    private func sign(png: Data, place: String, name: String) {
        do { try MoMEditor.sign(meeting, signerName: name, place: place, png: png, store: sidecars) }
        catch { errorMessage = error.localizedDescription }
    }

    private func removeSignature() {
        do { try MoMEditor.clearSignature(meeting, store: sidecars) }
        catch { errorMessage = error.localizedDescription }
    }

    private func ensureReference() {
        let date = meeting.scheduledStartTime ?? meeting.createdAt
        do { _ = try sidecars.referenceNumber(for: meeting.id, title: meeting.seriesName ?? meeting.title, date: date) }
        catch { errorMessage = error.localizedDescription }
    }
}
