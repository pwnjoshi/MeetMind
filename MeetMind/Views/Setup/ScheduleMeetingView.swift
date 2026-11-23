import SwiftUI
import SwiftData

/// Meeting details form (Figma "03 · Prepare a meeting"): new meeting, plan next meeting and follow-up.
public struct ScheduleMeetingView: View {
    @Bindable var viewModel: MeetingSetupViewModel
    public var onMeetingScheduled: ((Meeting) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]

    @State private var dateExpanded = false
    @State private var showsPeople = false
    @State private var showsDiscard = false
    @State private var showsSaveFailed = false
    @State private var showsRepeatPicker = false
    @State private var showsFollowUpPicker = false
    @State private var savedMeeting: Meeting?
    @State private var calendarNotice: String?
    @FocusState private var titleFocused: Bool

    public init(viewModel: MeetingSetupViewModel = MeetingSetupViewModel(), onMeetingScheduled: ((Meeting) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onMeetingScheduled = onMeetingScheduled
    }

    private var isFollowUp: Bool { viewModel.variant == .followUp }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    detailsBody
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PrepStyle.background.ignoresSafeArea())
            .navigationTitle(isFollowUp ? "Follow-Up" : "New Meeting")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    PrepCloseButton(systemName: isFollowUp ? "xmark" : "chevron.left") { requestClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    PrepConfirmButton(isEnabled: viewModel.isFormValid) { save() }
                }
            }
            .sheet(isPresented: $showsPeople) {
                AddPeopleSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showsRepeatPicker) {
                RepeatPickerSheet(recurrence: $viewModel.recurrence)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showsFollowUpPicker) {
                FollowUpPickerSheet(
                    candidates: MeetingFollowUpLink.candidates(forTitle: viewModel.title, in: meetings, limit: 200),
                    currentID: viewModel.followsUpOn?.id
                ) { chosen in
                    if chosen == nil && viewModel.followsUpOn == nil { return }
                    viewModel.setFollowsUp(chosen)
                }
            }
            .confirmationDialog(
                "Discard this meeting?",
                isPresented: $showsDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved meeting details will be lost.")
            }
            .alert("Couldn\u{2019}t Save Meeting", isPresented: $showsSaveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your edits are still here. Try again.")
            }
            .alert("Apple Calendar", isPresented: Binding(get: { calendarNotice != nil }, set: { if !$0 { calendarNotice = nil } })) {
                Button("OK") { finishAfterSave() }
            } message: {
                Text(calendarNotice ?? "")
            }
            .onAppear { prepare() }
        }
        .interactiveDismissDisabled(viewModel.hasUnsavedChanges)
    }

    // MARK: Meeting details

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            PrepSectionLabel(text: "MEETING")
                .font(.footnote)
            PrepCard {
                TextField("Title", text: $viewModel.title, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...5)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit { titleFocused = false }
                    .onChange(of: viewModel.title) { _, newValue in
                        if newValue.contains(where: \.isNewline) {
                            viewModel.title = newValue.filter { !$0.isNewline }
                            titleFocused = false
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(minHeight: 52, alignment: .leading)
                    .accessibilityLabel("Meeting title")
            }
            if let previous = viewModel.followsUpOn {
                Button {
                    dismissKeyboard()
                    showsFollowUpPicker = true
                } label: {
                    PrepPill(text: MeetingFollowUpLink.pillText(for: previous), systemImage: "arrow.turn.up.left")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .accessibilityHint("Changes the meeting this one follows up on")
            }
        }
    }

    @ViewBuilder
    private var detailsBody: some View {
        titleField
        PrepCard {
            dateSection
            Divider().padding(.leading, 16)
            repeatRow
            Divider().padding(.leading, 16)
            followUpRow
        }
        agendaSection
        openFromLastTimeSection
        peopleSection
        optionsSection
    }

    private var startBinding: Binding<Date> {
        Binding(get: { viewModel.startDate }, set: { viewModel.setStart($0) })
    }

    // MARK: Date and time

    private var dateSection: some View {
        VStack(spacing: 0) {
            Button {
                dismissKeyboard()
                withAnimation(.snappy) { dateExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.body)
                        .foregroundStyle(Color.red)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text("Date & Time")
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 12)
                    PrepDateTimeValue(start: viewModel.startDate, end: viewModel.endDate)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(dateExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(dateExpanded ? "Hides the date and time picker" : "Shows the date and time picker")

            if dateExpanded {
                Divider().padding(.leading, 16)
                MeetingDateTimeEditor(
                    start: $viewModel.startDate,
                    end: $viewModel.endDate,
                    error: viewModel.dateValidationError,
                    onStartChange: { viewModel.setStart($0) }
                )
            }
        }
    }

    // MARK: Repeat and follow-up

    private var repeatRow: some View {
        Button {
            dismissKeyboard()
            showsRepeatPicker = true
        } label: {
            rowLabel("Repeat", icon: ("repeat", Theme.Colors.manentAccent), value: MeetingRecurrence.title(for: viewModel.recurrence), chevron: "chevron.right")
        }
        .buttonStyle(.plain)
    }

    private var followUpRow: some View {
        Button {
            dismissKeyboard()
            showsFollowUpPicker = true
        } label: {
            rowLabel(
                "Follows up on",
                icon: ("arrow.turn.up.left", Color.purple),
                value: viewModel.followsUpOn?.title ?? "None",
                chevron: "chevron.right",
                valueLineLimit: 3
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Agenda

    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PrepSectionLabel(text: "AGENDA")
                .font(.footnote)
            PrepCard {
                PrepAgendaEditor(text: $viewModel.agendaText)
            }
        }
    }

    // MARK: Open from last time

    @ViewBuilder
    private var openFromLastTimeSection: some View {
        if let previous = viewModel.followsUpOn {
            let open = previous.actionItems
                .filter { !$0.isCompleted }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            if !open.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    PrepSectionLabel(text: "OPEN FROM LAST TIME")
                        .font(.footnote)
                    PrepCard {
                        ForEach(Array(open.enumerated()), id: \.element.id) { index, item in
                            openActionRow(item)
                            if index < open.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    Text("These stay on the meeting page. They are not added to the agenda.")
                        .font(.footnote)
                        .foregroundStyle(PrepStyle.secondaryText)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    private func openActionRow(_ item: ActionItem) -> some View {
        let due = PrepareMeetingFormat.due(item.dueDate)
        let owner = item.assignee?.name ?? "You"
        return VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Text(owner + (due.map { " \u{00B7} " + $0.text } ?? ""))
                .font(.subheadline)
                .foregroundStyle(PrepStyle.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PrepSectionLabel(text: "OPTIONS")
                .font(.footnote)
            PrepCard {
                Toggle(isOn: $viewModel.isImportant) {
                    HStack(spacing: 12) {
                        Image(systemName: "star.fill")
                            .font(.body)
                            .foregroundStyle(Color.orange)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        Text("Important")
                    }
                }
                .tint(Theme.Colors.manentAccent)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                Divider().padding(.leading, 16)
                NavigationLink {
                    AppleCalendarAccessView()
                } label: {
                    rowLabel(
                        "Add to Apple Calendar",
                        icon: ("calendar", Color.red),
                        value: viewModel.calendarService.isConnected ? "On" : "Off",
                        chevron: "chevron.right"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rowLabel(_ title: String, icon: (String, Color)? = nil, value: String, chevron: String, valueLineLimit: Int? = 1) -> some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon.0)
                    .font(.body)
                    .foregroundStyle(icon.1)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            Text(title)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(PrepStyle.secondaryText)
                .multilineTextAlignment(.trailing)
                .lineLimit(valueLineLimit)
            Image(systemName: chevron)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PrepSectionLabel(text: "PEOPLE")
                Spacer()
                Button("Edit") {
                    dismissKeyboard()
                    showsPeople = true
                }
                .foregroundStyle(Theme.Colors.manentAccent)
                .padding(.horizontal, 12)
            }
            PrepCard {
                ForEach(viewModel.participants, id: \.id) { person in
                    PrepPersonRow(speaker: person)
                        .contextMenu {
                            Button("Remove", systemImage: "person.badge.minus", role: .destructive) {
                                viewModel.removeParticipant(person)
                            }
                        }
                }
                Button {
                    dismissKeyboard()
                    showsPeople = true
                } label: {
                    Label("Add People", systemImage: "plus")
                        .foregroundStyle(Theme.Colors.manentAccent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
        }
    }

    // MARK: Actions

    private func dismissKeyboard() {
        titleFocused = false
        PrepKeyboard.dismiss()
    }

    /// Links a draft planned from a series to the latest recorded meeting of it, then records the baseline.
    private func prepare() {
        if viewModel.followsUpOn == nil, viewModel.followUpSource == nil, let seriesID = viewModel.scheduledSeriesID {
            viewModel.followsUpOn = MeetingFollowUpLink.previousRecorded(inSeries: seriesID, before: viewModel.startDate, in: meetings)
        }
        viewModel.prepareForEditing()
    }

    private func requestClose() {
        dismissKeyboard()
        if viewModel.hasUnsavedChanges {
            showsDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
        dismissKeyboard()
        do {
            let meeting = try viewModel.saveScheduledMeeting()
            savedMeeting = meeting
            if let notice = viewModel.calendarSyncMessage {
                calendarNotice = notice
            } else {
                finishAfterSave()
            }
        } catch {
            viewModel.errorMessage = error.localizedDescription
            showsSaveFailed = true
        }
    }

    private func finishAfterSave() {
        if let meeting = savedMeeting {
            onMeetingScheduled?(meeting)
        }
        savedMeeting = nil
        dismiss()
    }
}

/// Custom repeat interval ("Custom\u{2026}" in the Repeat list).
struct CustomRepeatSheet: View {
    @Binding var recurrence: MeetingRecurrence?
    /// Called after the interval was applied, so a parent picker can close too.
    var onApplied: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var interval = 1
    @State private var unit: MeetingRecurrence.Unit = .week

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $interval, in: 1...99) {
                    Text("Every \(interval) \(interval == 1 ? unit.singular.lowercased() : unit.singular.lowercased() + "s")")
                }
                Picker("Unit", selection: $unit) {
                    ForEach(MeetingRecurrence.Unit.allCases, id: \.self) { value in
                        Text(value.singular + "s").tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle("Custom Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { PrepCloseButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    PrepConfirmButton {
                        recurrence = MeetingRecurrence(unit: unit, interval: interval)
                        dismiss()
                        onApplied?()
                    }
                }
            }
            .onAppear {
                if let current = recurrence {
                    interval = current.interval
                    unit = current.unit
                }
            }
        }
    }
}

/// Repeat choices in a sheet: Never, the presets, the current custom interval and Custom.
struct RepeatPickerSheet: View {
    @Binding var recurrence: MeetingRecurrence?
    @Environment(\.dismiss) private var dismiss
    @State private var showsCustom = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    optionRow("Never", nil)
                    ForEach(MeetingRecurrence.presets, id: \.self) { preset in
                        optionRow(preset.title, preset)
                    }
                    if let current = recurrence, !current.isPreset {
                        optionRow(current.title, current)
                    }
                    Button {
                        showsCustom = true
                    } label: {
                        HStack {
                            Text("Custom\u{2026}").foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .navigationTitle("Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { PrepCloseButton { dismiss() } }
            }
            .sheet(isPresented: $showsCustom) {
                CustomRepeatSheet(recurrence: $recurrence, onApplied: { dismiss() })
                    .presentationDetents([.medium])
            }
        }
    }

    private func optionRow(_ title: String, _ value: MeetingRecurrence?) -> some View {
        Button {
            recurrence = value
            dismiss()
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer(minLength: 8)
                if recurrence == value {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.Colors.manentAccent)
                }
            }
            .contentShape(Rectangle())
        }
    }
}
