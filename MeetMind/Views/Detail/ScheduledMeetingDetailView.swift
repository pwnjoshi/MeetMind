import SwiftUI
import SwiftData

/// Full-screen "Prepare meeting" page for a scheduled meeting before capture begins (Figma D1).
/// Title, date, repeat, agenda and people edit a draft; Save writes it, Start Recording saves and begins capture.
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
    @State private var showsVidur = false
    /// Action items toggled on this page. They stay listed (checked) until the page closes.
    @State private var toggledActionIDs: Set<UUID> = []

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
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .onAppear { loadDraftIfNeeded() }
    }

    @ViewBuilder
    private func content(_ vm: MeetingSetupViewModel) -> some View {
        VStack(spacing: 0) {
            header(vm)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    titleBlock(vm)
                    agendaSection(vm)
                    openFromLastTimeSection
                    peopleSection(vm)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { startRecording(vm) } label: {
                Text("Start Recording")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.Colors.manentAccent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
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
        .sheet(isPresented: $showsVidur) {
            NavigationStack {
                RootAskAISheet(meetingId: meeting.id, modelContext: context) { showsVidur = false }
            }
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

    // MARK: Header

    private func header(_ vm: MeetingSetupViewModel) -> some View {
        HStack(spacing: 12) {
            Button {
                if vm.hasUnsavedChanges { showsDiscard = true } else { dismiss() }
            } label: {
                PrepareGlassIcon(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer(minLength: 0)

            Button { showsVidur = true } label: {
                PrepareGlassIcon(systemName: "sparkles", tint: Theme.Colors.manentAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask Vidur")

            moreMenu(vm)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private func moreMenu(_ vm: MeetingSetupViewModel) -> some View {
        Menu {
            Button { showsTitleSheet = true } label: { Label("Edit Title", systemImage: "pencil") }
            Button { showsDatePopover = true } label: { Label("Date & Time", systemImage: "calendar") }
            Button { showsPeople = true } label: { Label("Add People", systemImage: "person.badge.plus") }
            Menu {
                Button { vm.coordinatorID = nil } label: {
                    checkLabel(UserProfile.defaultLocalName, vm.coordinatorID == nil)
                }
                ForEach(vm.participants, id: \.id) { person in
                    Button { vm.coordinatorID = person.id } label: {
                        checkLabel(person.name, vm.coordinatorID == person.id)
                    }
                }
            } label: {
                Label("Minutes Coordinator", systemImage: "person.text.rectangle")
            }
            Divider()
            Button { save(vm) } label: { Label("Save Changes", systemImage: "checkmark") }
                .disabled(!vm.hasUnsavedChanges || !vm.isFormValid)
        } label: {
            PrepareGlassIcon(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    // MARK: Title, date, repeat

    private func titleBlock(_ vm: MeetingSetupViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { showsTitleSheet = true } label: {
                Text(vm.title.isEmpty ? meeting.title : vm.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits the title")

            Button { showsDatePopover = true } label: {
                Text(PrepareMeetingFormat.subtitle(start: vm.startDate, end: vm.endDate))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.manentAccent)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Changes the date and time")
            .popover(isPresented: $showsDatePopover) {
                MeetingDateTimePopover(date: Binding(get: { vm.startDate }, set: { vm.setStart($0) }))
                    .presentationCompactAdaptation(.popover)
            }

            repeatPill(vm)
        }
    }

    private func repeatPill(_ vm: MeetingSetupViewModel) -> some View {
        Menu {
            Button { vm.recurrence = nil } label: { checkLabel("Never", vm.recurrence == nil) }
            ForEach(MeetingRecurrence.presets, id: \.self) { option in
                Button { vm.recurrence = option } label: { checkLabel(option.title, vm.recurrence == option) }
            }
            Divider()
            Button("Custom\u{2026}") { showsCustomRepeat = true }
        } label: {
            HStack(spacing: 6) {
                Text(vm.recurrence?.summaryText ?? "Does not repeat")
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.Colors.manentAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.Colors.manentAccent.opacity(0.14), in: Capsule())
        }
        .accessibilityLabel("Repeat")
        .accessibilityValue(vm.recurrence?.summaryText ?? "Does not repeat")
    }

    // MARK: Agenda

    private func agendaSection(_ vm: MeetingSetupViewModel) -> some View {
        let items = PrepareMeetingFormat.agendaItems(from: vm.agendaText)
        return VStack(alignment: .leading, spacing: 10) {
            PrepareSectionHeader("Agenda") {
                Button("Edit") { showsAgendaSheet = true }
                    .foregroundStyle(Theme.Colors.manentAccent)
            }
            PrepCard {
                if items.isEmpty {
                    Button { showsAgendaSheet = true } label: {
                        Text("Add agenda")
                            .foregroundStyle(Theme.Colors.manentAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text("\(index + 1)")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.Colors.manentAccent)
                                .frame(minWidth: 20, alignment: .leading)
                            Text(item)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .accessibilityElement(children: .combine)
                        if index < items.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }

    // MARK: Open from last time

    /// The most recent earlier meeting of the same series that has already been held.
    private var previousMeeting: Meeting? {
        let series = MoMDocumentBuilder.seriesMeetings(of: meeting, in: meetings)
        guard let index = series.firstIndex(where: { $0.id == meeting.id }) else { return nil }
        return series[..<index].last(where: { $0.status != .scheduled })
    }

    private func openActions(of previous: Meeting) -> [ActionItem] {
        previous.actionItems
            .filter { !$0.isCompleted || toggledActionIDs.contains($0.id) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    @ViewBuilder
    private var openFromLastTimeSection: some View {
        if let previous = previousMeeting {
            let items = openActions(of: previous)
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    PrepareSectionHeader("Open From Last Time")
                    PrepCard {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            openActionRow(item, previous: previous)
                            if index < items.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
    }

    private func openActionRow(_ item: ActionItem, previous: Meeting) -> some View {
        let due = PrepareMeetingFormat.due(item.dueDate)
        let owner = item.assignee?.name ?? "You"
        return HStack(spacing: 12) {
            Button { toggle(item) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(item.isCompleted ? Theme.Colors.manentAccent : Color(uiColor: .systemGray3))
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Mark \(item.title) as not done" : "Mark \(item.title) as done")

            NavigationLink {
                MeetingDetailContainerView(meetingId: previous.id)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .foregroundStyle(.primary)
                            .strikethrough(item.isCompleted)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 0) {
                            Text(owner + (due == nil ? "" : " \u{00B7} "))
                                .foregroundStyle(PrepStyle.secondaryText)
                            if let due {
                                Text(due.text)
                                    .foregroundStyle(due.isUrgent ? Color.orange : PrepStyle.secondaryText)
                            }
                        }
                        .font(.subheadline)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func toggle(_ item: ActionItem) {
        let previousCompleted = item.isCompleted
        let previousCompletedAt = item.completedAt
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? Date() : nil
        toggledActionIDs.insert(item.id)
        do {
            try context.save()
        } catch {
            item.isCompleted = previousCompleted
            item.completedAt = previousCompletedAt
            showsSaveFailed = true
        }
    }

    // MARK: People

    private func peopleSection(_ vm: MeetingSetupViewModel) -> some View {
        let people = vm.participants
        return VStack(alignment: .leading, spacing: 10) {
            PrepareSectionHeader("People") {
                if !people.isEmpty {
                    Text("\(people.count)")
                        .foregroundStyle(Theme.Colors.manentAccent)
                        .accessibilityLabel("\(people.count) people")
                }
            }
            PrepCard {
                Button { showsPeople = true } label: {
                    HStack(spacing: 12) {
                        if !people.isEmpty {
                            PrepareAvatarStack(people: people)
                        }
                        Text(PrepareMeetingFormat.peopleSummary(people.map(\.name)))
                            .foregroundStyle(people.isEmpty ? Theme.Colors.manentAccent : PrepStyle.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edits the people in this meeting")
            }
        }
    }

    // MARK: Helpers

    private func checkLabel(_ title: String, _ selected: Bool) -> some View {
        Group {
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
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
