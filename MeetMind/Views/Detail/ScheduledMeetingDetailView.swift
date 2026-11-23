import SwiftUI
import SwiftData

/// Full-screen "Prepare meeting" page for a scheduled meeting before capture begins (Figma D1).
/// Everything is edited in place: tap the title, the date line, the repeat or follows-up pill, the agenda
/// or the people row. Changes save automatically when leaving the page or starting the recording.
public struct ScheduledMeetingDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let meeting: Meeting
    @Query private var meetings: [Meeting]
    @State private var draft: MeetingSetupViewModel?
    @State private var showsDateSheet = false
    @State private var showsPeople = false
    @State private var showsDiscard = false
    @State private var showsSaveFailed = false
    @State private var showsRepeatPicker = false
    @State private var showsFollowUpPicker = false
    @State private var showsVidur = false
    @State private var showsCalendarAccess = false
    @State private var showsDeleteConfirm = false
    @State private var showsDeleteFailed = false
    @State private var isDeleted = false
    @State private var calendarEventID: String?
    @State private var notice: PageNotice?
    /// Action items toggled on this page. They stay listed (checked) until the page closes.
    @State private var toggledActionIDs: Set<UUID> = []
    @FocusState private var titleFocused: Bool

    /// Short message shown in an alert (calendar result, duplicate result).
    private struct PageNotice: Equatable {
        let title: String
        let message: String
    }

    public init(meeting: Meeting) {
        self.meeting = meeting
    }

    public var body: some View {
        Group {
            if isDeleted {
                Color.clear
            } else if let draft {
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
        .onDisappear { autosaveOnLeave() }
    }

    @ViewBuilder
    private func content(_ vm: MeetingSetupViewModel) -> some View {
        VStack(spacing: 0) {
            header(vm)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    titleBlock(vm)
                    agendaSection(vm)
                    openFromLastTimeSection(vm)
                    peopleSection(vm)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
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
        .sheet(isPresented: $showsDateSheet) {
            MeetingDateTimeSheet(
                start: Binding(get: { vm.startDate }, set: { vm.startDate = $0 }),
                end: Binding(get: { vm.endDate }, set: { vm.endDate = $0 }),
                error: vm.dateValidationError,
                onStartChange: { vm.setStart($0) }
            )
        }
        .sheet(isPresented: $showsPeople) { AddPeopleSheet(viewModel: vm) }
        .sheet(isPresented: $showsRepeatPicker) {
            RepeatPickerSheet(recurrence: Binding(get: { vm.recurrence }, set: { vm.recurrence = $0 }))
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showsFollowUpPicker) {
            FollowUpPickerSheet(
                candidates: MeetingFollowUpLink.candidates(forTitle: vm.title, excluding: meeting.id, in: meetings, limit: 200),
                currentID: vm.followsUpOn?.id
            ) { chosen in
                // "None" while nothing is linked changes nothing (the meeting may still belong to a repeat series).
                if chosen == nil && vm.followsUpOn == nil { return }
                vm.setFollowsUp(chosen)
            }
        }
        .sheet(isPresented: $showsCalendarAccess) {
            NavigationStack {
                AppleCalendarAccessView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            PrepConfirmButton { showsCalendarAccess = false }
                        }
                    }
            }
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
            Text("The end time must be after the start time, so these changes can\u{2019}t be saved.")
        }
        .confirmationDialog("Delete this meeting?", isPresented: $showsDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Meeting", role: .destructive) { deleteMeeting(vm) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The meeting, its agenda and its notes are removed from this device. This can\u{2019}t be undone.")
        }
        .alert("Couldn\u{2019}t Save Meeting", isPresented: $showsSaveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your edits are still here. Try again.")
        }
        .alert("Couldn\u{2019}t Delete Meeting", isPresented: $showsDeleteFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The meeting could not be fully removed. Try again.")
        }
        .alert(
            notice?.title ?? "",
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice?.message ?? "")
        }
    }

    // MARK: Header

    private func header(_ vm: MeetingSetupViewModel) -> some View {
        HStack(spacing: 12) {
            Button {
                leave(vm)
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

    /// Only actions that have no place on the page itself. Title, date, repeat, follows-up, agenda and
    /// people are edited in place.
    private func moreMenu(_ vm: MeetingSetupViewModel) -> some View {
        Menu {
            if calendarEventID != nil {
                Button { openInCalendar(vm) } label: { Label("Open in Calendar", systemImage: "calendar") }
            } else {
                Button { addToCalendar(vm) } label: { Label("Add to Calendar", systemImage: "calendar.badge.plus") }
            }
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
            Button { duplicate(vm) } label: { Label("Duplicate Meeting", systemImage: "plus.square.on.square") }
            Divider()
            Button(role: .destructive) { showsDeleteConfirm = true } label: { Label("Delete Meeting", systemImage: "trash") }
        } label: {
            PrepareGlassIcon(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    // MARK: Title, date, repeat, follows up, important

    private func titleBlock(_ vm: MeetingSetupViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: Binding(get: { vm.title }, set: { vm.title = $0 }), axis: .vertical)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1...8)
                .focused($titleFocused)
                .submitLabel(.done)
                .onSubmit { titleFocused = false }
                .onChange(of: vm.title) { _, newValue in
                    if newValue.contains(where: \.isNewline) {
                        vm.title = newValue.filter { !$0.isNewline }
                        titleFocused = false
                    }
                }
                .accessibilityLabel("Meeting title")

            Button {
                dismissKeyboard()
                showsDateSheet = true
            } label: {
                Text(PrepareMeetingFormat.subtitle(start: vm.startDate, end: vm.endDate))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.manentAccent)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Changes the date and time")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    repeatPill(vm)
                    importantPill(vm)
                }
                VStack(alignment: .leading, spacing: 8) {
                    repeatPill(vm)
                    importantPill(vm)
                }
            }
            followUpPill(vm)
        }
    }

    private func repeatPill(_ vm: MeetingSetupViewModel) -> some View {
        Button {
            dismissKeyboard()
            showsRepeatPicker = true
        } label: {
            PrepPill(text: vm.recurrence?.summaryText ?? "Does not repeat", systemImage: "repeat")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Repeat")
        .accessibilityValue(vm.recurrence?.summaryText ?? "Does not repeat")
    }

    private func importantPill(_ vm: MeetingSetupViewModel) -> some View {
        Button {
            dismissKeyboard()
            vm.isImportant.toggle()
        } label: {
            PrepPill(
                text: "Important",
                systemImage: vm.isImportant ? "star.fill" : "star",
                tint: vm.isImportant ? Color.orange : Theme.Colors.manentAccent,
                trailingSymbol: nil,
                isFilled: vm.isImportant
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Important")
        .accessibilityValue(vm.isImportant ? "On" : "Off")
        .accessibilityHint("Highlights this meeting on Home")
    }

    private func followUpPill(_ vm: MeetingSetupViewModel) -> some View {
        Button {
            dismissKeyboard()
            showsFollowUpPicker = true
        } label: {
            if let previous = vm.followsUpOn {
                PrepPill(text: MeetingFollowUpLink.pillText(for: previous), systemImage: "arrow.turn.up.left")
            } else {
                PrepPill(text: "Follows up on\u{2026}", systemImage: "arrow.turn.up.left", tint: PrepStyle.secondaryText, trailingSymbol: nil)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Follows up on")
        .accessibilityValue(vm.followsUpOn?.title ?? "None")
        .accessibilityHint("Changes the meeting this one follows up on")
    }

    // MARK: Agenda

    private func agendaSection(_ vm: MeetingSetupViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PrepareSectionHeader("Agenda")
            PrepCard {
                PrepAgendaEditor(text: Binding(get: { vm.agendaText }, set: { vm.agendaText = $0 }))
            }
        }
    }

    // MARK: Open from last time

    private func openActions(of previous: Meeting) -> [ActionItem] {
        previous.actionItems
            .filter { !$0.isCompleted || toggledActionIDs.contains($0.id) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    @ViewBuilder
    private func openFromLastTimeSection(_ vm: MeetingSetupViewModel) -> some View {
        if let previous = vm.followsUpOn {
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
                Button {
                    dismissKeyboard()
                    showsPeople = true
                } label: {
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

    private func dismissKeyboard() {
        titleFocused = false
        PrepKeyboard.dismiss()
    }

    private func loadDraftIfNeeded() {
        guard draft == nil, !isDeleted else { return }
        let vm = MeetingSetupViewModel(modelContext: context)
        let start = meeting.scheduledStartTime ?? meeting.createdAt
        vm.title = meeting.title
        vm.startDate = start
        vm.endDate = start.addingTimeInterval(max(900, meeting.duration))
        vm.agendaText = meeting.agendaText ?? ""
        vm.participants = meeting.participants
        vm.isImportant = meeting.isFavorite
        vm.scheduledSeriesID = meeting.seriesID
        vm.scheduledSeriesName = meeting.seriesName
        if let seriesID = meeting.seriesID {
            vm.followsUpOn = MeetingFollowUpLink.previousRecorded(inSeries: seriesID, before: start, excluding: meeting.id, in: meetings)
        }
        let record = vm.prepStore.record(for: meeting.id)
        vm.recurrence = record.recurrence
        vm.coordinatorID = record.coordinatorID
        calendarEventID = (record.calendarEventID ?? "").isEmpty ? nil : record.calendarEventID
        vm.captureDraftBaseline()
        draft = vm
    }

    /// Writes the draft to the meeting. Returns false and shows the failure alert when saving fails.
    @discardableResult
    private func apply(_ vm: MeetingSetupViewModel) -> Bool {
        guard vm.isFormValid else { return false }
        let trimmedTitle = vm.title.trimmingCharacters(in: .whitespacesAndNewlines)

        let oldStart = meeting.scheduledStartTime ?? meeting.createdAt
        let oldTitle = meeting.title
        let oldAgenda = meeting.agendaText
        let oldSeriesID = meeting.seriesID
        let oldRecord = vm.prepStore.record(for: meeting.id)
        let previousMeeting = vm.followsUpOn
        let previousSeriesID = previousMeeting?.seriesID
        let previousSeriesName = previousMeeting?.seriesName
        let snapshot = (
            title: meeting.title,
            start: meeting.scheduledStartTime,
            duration: meeting.duration,
            agenda: meeting.agendaText,
            participants: meeting.participants,
            isFavorite: meeting.isFavorite,
            seriesID: meeting.seriesID,
            seriesName: meeting.seriesName
        )

        if !trimmedTitle.isEmpty { meeting.title = trimmedTitle }
        meeting.scheduledStartTime = vm.startDate
        meeting.duration = max(0, vm.endDate.timeIntervalSince(vm.startDate))
        let agenda = vm.agendaText.trimmingCharacters(in: .whitespacesAndNewlines)
        meeting.agendaText = agenda.isEmpty ? nil : agenda
        meeting.participants = vm.participants
        meeting.isFavorite = vm.isImportant
        MeetingFollowUpLink.apply(seriesID: vm.scheduledSeriesID, seriesName: vm.scheduledSeriesName, previous: previousMeeting, to: meeting)
        do {
            try context.save()
        } catch {
            meeting.title = snapshot.title
            meeting.scheduledStartTime = snapshot.start
            meeting.duration = snapshot.duration
            meeting.agendaText = snapshot.agenda
            meeting.participants = snapshot.participants
            meeting.isFavorite = snapshot.isFavorite
            meeting.seriesID = snapshot.seriesID
            meeting.seriesName = snapshot.seriesName
            previousMeeting?.seriesID = previousSeriesID
            previousMeeting?.seriesName = previousSeriesName
            showsSaveFailed = true
            return false
        }

        MeetingRepeatEditing.removeStaleOccurrence(
            of: meeting,
            oldStart: oldStart,
            oldTitle: oldTitle,
            oldAgenda: oldAgenda,
            oldSeriesID: oldSeriesID,
            oldRecurrence: oldRecord.recurrence,
            newStart: vm.startDate,
            newRecurrence: vm.recurrence,
            context: context,
            store: vm.prepStore
        )
        let chosenRecurrence = vm.recurrence
        let chosenCoordinator = vm.coordinatorID
        vm.prepStore.update(meeting.id) {
            $0.recurrence = chosenRecurrence
            $0.coordinatorID = chosenCoordinator
        }
        vm.finalizePreparation(for: meeting)
        vm.captureDraftBaseline()
        let storedEvent = vm.prepStore.record(for: meeting.id).calendarEventID ?? ""
        calendarEventID = storedEvent.isEmpty ? nil : storedEvent
        return true
    }

    /// Back button: saves the edits and leaves. Only an invalid time range asks before discarding.
    private func leave(_ vm: MeetingSetupViewModel) {
        dismissKeyboard()
        if !vm.hasUnsavedChanges {
            dismiss()
        } else if !vm.isFormValid {
            showsDiscard = true
        } else if apply(vm) {
            dismiss()
        }
    }

    /// Covers leaving without the back button (swipe back, opening a linked meeting).
    private func autosaveOnLeave() {
        guard !isDeleted, let vm = draft, vm.hasUnsavedChanges, vm.isFormValid else { return }
        apply(vm)
    }

    private func startRecording(_ vm: MeetingSetupViewModel) {
        dismissKeyboard()
        if vm.hasUnsavedChanges, !apply(vm) { return }
        meeting.status = .recording
        do {
            try context.save()
        } catch {
            meeting.status = .scheduled
            showsSaveFailed = true
        }
    }

    // MARK: More menu actions

    private func addToCalendar(_ vm: MeetingSetupViewModel) {
        guard vm.calendarService.isConnected else {
            showsCalendarAccess = true
            return
        }
        if vm.hasUnsavedChanges, !apply(vm) { return }
        do {
            let existing = vm.prepStore.record(for: meeting.id).calendarEventID
            let identifier = try vm.calendarService.upsertEvent(for: meeting, existingIdentifier: existing)
            vm.prepStore.update(meeting.id) { $0.calendarEventID = identifier }
            calendarEventID = identifier.isEmpty ? nil : identifier
            notice = PageNotice(title: "Apple Calendar", message: "The meeting was added to your calendar.")
        } catch {
            notice = PageNotice(title: "Apple Calendar", message: "The meeting could not be added to your calendar.")
        }
    }

    private func openInCalendar(_ vm: MeetingSetupViewModel) {
        let seconds = Int(vm.startDate.timeIntervalSinceReferenceDate)
        if let url = URL(string: "calshow:\(seconds)") {
            openURL(url)
        }
    }

    private func duplicate(_ vm: MeetingSetupViewModel) {
        if vm.hasUnsavedChanges, !apply(vm) { return }
        let start = meeting.scheduledStartTime ?? meeting.createdAt
        var newStart = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
        if newStart <= Date() {
            newStart = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / 3600).rounded(.up) * 3600)
        }
        let copy = Meeting(
            title: meeting.title,
            createdAt: Date(),
            scheduledStartTime: newStart,
            duration: meeting.duration,
            status: .scheduled,
            isFavorite: meeting.isFavorite,
            templateName: meeting.templateName,
            folder: meeting.folder
        )
        copy.agendaText = meeting.agendaText
        copy.tags = meeting.tags
        copy.participants = meeting.participants.map {
            Speaker(name: $0.name, email: $0.email, role: $0.role, avatarColorHex: $0.avatarColorHex)
        }
        context.insert(copy)
        do {
            try context.save()
            let when = newStart.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
            notice = PageNotice(title: "Meeting Duplicated", message: "A copy was scheduled for \(when).")
        } catch {
            context.delete(copy)
            showsSaveFailed = true
        }
    }

    private func deleteMeeting(_ vm: MeetingSetupViewModel) {
        // Hide the page first so nothing reads the meeting while it is being removed.
        isDeleted = true
        Task { @MainActor in
            do {
                _ = try await DeletionCoordinator(modelContext: context).deleteMeeting(meeting)
                dismiss()
            } catch {
                isDeleted = false
                showsDeleteFailed = true
            }
        }
    }
}
