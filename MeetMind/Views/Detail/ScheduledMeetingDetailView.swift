import SwiftUI
import SwiftData

/// Preparation record for a scheduled meeting before capture begins (Figma "Meeting details").
public struct ScheduledMeetingDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let meeting: Meeting
    @Query private var meetings: [Meeting]
    @State private var draft: MeetingSetupViewModel?
    @State private var showsTitleSheet = false
    @State private var showsAgendaSheet = false
    @State private var showsDatePopover = false
    @State private var showsPeople = false
    @State private var showsDiscard = false
    @State private var showsSaveFailed = false
    @State private var showsCustomRepeat = false

    public init(meeting: Meeting) {
        self.meeting = meeting
    }

    public var body: some View {
        Group {
            if let draft {
                content(draft)
            } else {
                Color.clear
            }
        }
        .background(PrepStyle.background.ignoresSafeArea())
        .onAppear { loadDraftIfNeeded() }
    }

    @ViewBuilder
    private func content(_ vm: MeetingSetupViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Button { showsTitleSheet = true } label: {
                    Text(vm.title.isEmpty ? meeting.title : vm.title)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                detailsCard(vm)
                peopleSection(vm)
                earlierMeetings
                minutesSection(vm)
                Color.clear.frame(height: 90)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                PrepCloseButton(systemName: "chevron.left") {
                    if vm.hasUnsavedChanges { showsDiscard = true } else { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                PrepConfirmButton(isEnabled: vm.isFormValid) { save(vm) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { startRecording(vm) } label: {
                Text("Start recording").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Theme.Colors.manentAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showsTitleSheet) {
            PrepTextEntrySheet(
                title: "Title",
                placeholder: "Title",
                suggestionsTitle: "Suggestions",
                suggestions: ["Weekly team sync", "Finance review", "Launch readiness"],
                text: Binding(get: { vm.title }, set: { vm.title = $0 })
            )
        }
        .sheet(isPresented: $showsAgendaSheet) {
            PrepTextEntrySheet(
                title: "Agenda",
                placeholder: "Agenda",
                suggestionsTitle: "Suggested Topics",
                suggestions: ["Progress, blockers and next steps"],
                multiline: true,
                text: Binding(get: { vm.agendaText }, set: { vm.agendaText = $0 })
            )
        }
        .sheet(isPresented: $showsPeople) { AddPeopleSheet(viewModel: vm) }
        .sheet(isPresented: $showsCustomRepeat) {
            CustomRepeatSheet(recurrence: Binding(get: { vm.recurrence }, set: { vm.recurrence = $0 }))
                .presentationDetents([.medium])
        }
        .confirmationDialog("Discard Changes?", isPresented: $showsDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your changes to this meeting haven\u{2019}t been saved.")
        }
        .alert("Couldn\u{2019}t Save Meeting", isPresented: $showsSaveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your edits are still here. Try again.")
        }
    }

    // MARK: Sections

    private func detailsCard(_ vm: MeetingSetupViewModel) -> some View {
        PrepCard {
            Button { showsDatePopover = true } label: {
                row("Date & Time", value: dateText(vm.startDate), chevron: "chevron.right")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showsDatePopover) {
                MeetingDateTimePopover(date: Binding(get: { vm.startDate }, set: { vm.setStart($0) }))
                    .presentationCompactAdaptation(.popover)
            }
            Divider().padding(.leading, 16)
            Menu {
                Button { vm.recurrence = nil } label: { checkLabel("Never", vm.recurrence == nil) }
                ForEach(MeetingRecurrence.presets, id: \.self) { option in
                    Button { vm.recurrence = option } label: { checkLabel(option.title, vm.recurrence == option) }
                }
                Divider()
                Button("Custom\u{2026}") { showsCustomRepeat = true }
            } label: {
                row("Repeat", value: MeetingRecurrence.title(for: vm.recurrence), chevron: "chevron.up.chevron.down")
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 16)
            Button { showsAgendaSheet = true } label: {
                row("Agenda", value: agendaPreview(vm.agendaText), chevron: "chevron.right")
            }
            .buttonStyle(.plain)
        }
    }

    private func peopleSection(_ vm: MeetingSetupViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PrepSectionLabel(text: "People")
                Spacer()
                Button("Edit") { showsPeople = true }
                    .foregroundStyle(Theme.Colors.manentAccent)
                    .padding(.horizontal, 12)
            }
            PrepCard {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .foregroundStyle(Color(uiColor: .systemGray3))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UserProfile.defaultLocalName)
                    }
                    Spacer()
                    Text("Organizer").foregroundStyle(PrepStyle.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .accessibilityElement(children: .combine)
                ForEach(vm.participants, id: \.id) { person in
                    PrepPersonRow(speaker: person)
                        .contextMenu {
                            Button("Remove", systemImage: "person.badge.minus", role: .destructive) {
                                vm.removeParticipant(person)
                            }
                        }
                }
                Button("Add People") { showsPeople = true }
                    .foregroundStyle(Theme.Colors.manentAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }

    private var earlier: [Meeting] {
        guard let seriesID = meeting.seriesID else { return [] }
        return meetings
            .filter { $0.seriesID == seriesID && $0.id != meeting.id && $0.status != .scheduled }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @ViewBuilder
    private var earlierMeetings: some View {
        if !earlier.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                PrepSectionLabel(text: "Earlier meetings")
                PrepCard {
                    ForEach(earlier, id: \.id) { prior in
                        NavigationLink {
                            MeetingDetailContainerView(meetingId: prior.id)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(spacing: 0) {
                                    Text(prior.createdAt.formatted(.dateTime.month(.abbreviated)).uppercased())
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Theme.Colors.coralRed)
                                    Text(prior.createdAt.formatted(.dateTime.day()))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                }
                                .frame(width: 40, height: 40)
                                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(prior.title).foregroundStyle(.primary)
                                    Text(prior.figmaBadgeText).font(.subheadline).foregroundStyle(PrepStyle.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func minutesSection(_ vm: MeetingSetupViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PrepSectionLabel(text: "Minutes")
            PrepCard {
                Menu {
                    Button { vm.coordinatorID = nil } label: {
                        if vm.coordinatorID == nil {
                            Label { Text(UserProfile.defaultLocalName); Text("You") } icon: { Image(systemName: "checkmark") }
                        } else {
                            Text(UserProfile.defaultLocalName); Text("You")
                        }
                    }
                    ForEach(vm.participants, id: \.id) { person in
                        Button { vm.coordinatorID = person.id } label: {
                            checkLabel(person.name, vm.coordinatorID == person.id)
                        }
                    }
                } label: {
                    row("Coordinator", value: coordinatorName(vm), chevron: "chevron.up.chevron.down")
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 16)
                row("Minutes Format", value: meeting.templateName ?? "Project review", chevron: nil)
            }
        }
    }

    // MARK: Helpers

    private func row(_ title: String, value: String, chevron: String?) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(PrepStyle.secondaryText).lineLimit(1)
            if let chevron {
                Image(systemName: chevron)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private func checkLabel(_ title: String, _ selected: Bool) -> some View {
        Group {
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + ", " + date.formatted(date: .omitted, time: .shortened)
    }

    private func agendaPreview(_ text: String) -> String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return first.isEmpty ? "Add agenda" : first
    }

    private func coordinatorName(_ vm: MeetingSetupViewModel) -> String {
        guard let id = vm.coordinatorID, let person = vm.participants.first(where: { $0.id == id }) else {
            return UserProfile.defaultLocalName
        }
        return person.name
    }

    private func loadDraftIfNeeded() {
        guard draft == nil else { return }
        let vm = MeetingSetupViewModel(modelContext: context)
        let start = meeting.scheduledStartTime ?? meeting.createdAt
        vm.title = meeting.title
        vm.startDate = start
        vm.endDate = start.addingTimeInterval(max(900, meeting.duration))
        vm.agendaText = meeting.agendaText ?? ""
        vm.participants = meeting.participants
        vm.scheduledSeriesID = meeting.seriesID
        vm.scheduledSeriesName = meeting.seriesName
        let record = vm.prepStore.record(for: meeting.id)
        vm.recurrence = record.recurrence
        vm.coordinatorID = record.coordinatorID
        vm.captureDraftBaseline()
        draft = vm
    }

    /// Writes the draft to the meeting. Returns false and shows the failure alert when saving fails.
    @discardableResult
    private func apply(_ vm: MeetingSetupViewModel) -> Bool {
        guard vm.isFormValid else { return false }
        let trimmedTitle = vm.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = (meeting.title, meeting.scheduledStartTime, meeting.duration, meeting.agendaText, meeting.participants)
        if !trimmedTitle.isEmpty { meeting.title = trimmedTitle }
        meeting.scheduledStartTime = vm.startDate
        meeting.duration = max(0, vm.endDate.timeIntervalSince(vm.startDate))
        let agenda = vm.agendaText.trimmingCharacters(in: .whitespacesAndNewlines)
        meeting.agendaText = agenda.isEmpty ? nil : agenda
        meeting.participants = vm.participants
        do {
            try context.save()
        } catch {
            meeting.title = previous.0
            meeting.scheduledStartTime = previous.1
            meeting.duration = previous.2
            meeting.agendaText = previous.3
            meeting.participants = previous.4
            showsSaveFailed = true
            return false
        }
        let chosenRecurrence = vm.recurrence
        let chosenCoordinator = vm.coordinatorID
        vm.prepStore.update(meeting.id) {
            $0.recurrence = chosenRecurrence
            $0.coordinatorID = chosenCoordinator
        }
        vm.finalizePreparation(for: meeting)
        vm.captureDraftBaseline()
        return true
    }

    private func save(_ vm: MeetingSetupViewModel) {
        if apply(vm) { dismiss() }
    }

    private func startRecording(_ vm: MeetingSetupViewModel) {
        if vm.hasUnsavedChanges, !apply(vm) { return }
        meeting.status = .recording
        do {
            try context.save()
        } catch {
            meeting.status = .scheduled
            showsSaveFailed = true
        }
    }
}
