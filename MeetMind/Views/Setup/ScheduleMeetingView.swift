import SwiftUI
import SwiftData

/// Meeting details form (Figma "03 · Prepare a meeting"): new meeting, plan next meeting and follow-up.
public struct ScheduleMeetingView: View {
    @Bindable var viewModel: MeetingSetupViewModel
    public var onMeetingScheduled: ((Meeting) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]

    @State private var showsTitleSheet = false
    @State private var showsAgendaSheet = false
    @State private var showsDatePopover = false
    @State private var showsPeople = false
    @State private var showsDiscard = false
    @State private var showsSaveFailed = false
    @State private var showsCustomRepeat = false
    @State private var showsNewSeries = false
    @State private var showsRenameSeries = false
    @State private var showsSeries = false
    @State private var seriesNameDraft = ""
    @State private var savedMeeting: Meeting?
    @State private var calendarNotice: String?

    public init(viewModel: MeetingSetupViewModel = MeetingSetupViewModel(), onMeetingScheduled: ((Meeting) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onMeetingScheduled = onMeetingScheduled
    }

    private var isFollowUp: Bool { viewModel.variant == .followUp }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isFollowUp {
                        followUpBody
                    } else {
                        detailsBody
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PrepStyle.background.ignoresSafeArea())
            .navigationTitle(isFollowUp ? "Follow-Up" : "")
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
            .safeAreaInset(edge: .bottom) {
                if !isFollowUp {
                    Button { save() } label: {
                        Text("Schedule meeting").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(Theme.Colors.manentAccent)
                    .disabled(!viewModel.isFormValid)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .navigationDestination(isPresented: $showsSeries) {
                if let id = viewModel.scheduledSeriesID {
                    SeriesComparisonView(seriesID: id, seriesName: viewModel.scheduledSeriesName ?? "Series")
                }
            }
            .sheet(isPresented: $showsTitleSheet) {
                PrepTextEntrySheet(
                    title: "Title",
                    placeholder: "Title",
                    suggestionsTitle: "Suggestions",
                    suggestions: ["Weekly team sync", "Finance review", "Launch readiness"],
                    text: $viewModel.title
                )
            }
            .sheet(isPresented: $showsAgendaSheet) {
                PrepTextEntrySheet(
                    title: "Agenda",
                    placeholder: "Agenda",
                    suggestionsTitle: "Suggested Topics",
                    suggestions: ["Progress, blockers and next steps"],
                    multiline: true,
                    text: $viewModel.agendaText
                )
            }
            .sheet(isPresented: $showsPeople) {
                AddPeopleSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showsCustomRepeat) {
                CustomRepeatSheet(recurrence: $viewModel.recurrence)
                    .presentationDetents([.medium])
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
            .alert("New Series", isPresented: $showsNewSeries) {
                TextField("Series name", text: $seriesNameDraft)
                Button("Cancel", role: .cancel) {}
                Button("Create") { createSeries() }
            }
            .alert("Rename Series", isPresented: $showsRenameSeries) {
                TextField("Series name", text: $seriesNameDraft)
                Button("Cancel", role: .cancel) {}
                Button("Save") { renameSeries() }
            }
            .onAppear { viewModel.prepareForEditing() }
        }
        .interactiveDismissDisabled(viewModel.hasUnsavedChanges)
    }

    // MARK: Meeting details

    private var titleButton: some View {
        Button { showsTitleSheet = true } label: {
            Text(viewModel.title.isEmpty ? "Title" : viewModel.title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(viewModel.title.isEmpty ? Color(uiColor: .placeholderText) : Color.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Meeting title")
        .accessibilityValue(viewModel.title)
    }

    @ViewBuilder
    private var detailsBody: some View {
        titleButton
        PrepCard {
            dateRow
            Divider().padding(.leading, 16)
            repeatRow
            Divider().padding(.leading, 16)
            agendaRow
            if showsSeriesRow {
                Divider().padding(.leading, 16)
                seriesRow
            }
            Divider().padding(.leading, 16)
            calendarRow
        }
        if let error = viewModel.dateValidationError {
            Text(error).font(.footnote).foregroundStyle(Theme.Colors.coralRed).padding(.horizontal, 16)
        }
        peopleSection
    }

    private var startBinding: Binding<Date> {
        Binding(get: { viewModel.startDate }, set: { viewModel.setStart($0) })
    }

    private var dateRow: some View {
        Button { showsDatePopover = true } label: {
            rowLabel("Date & Time", value: viewModel.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + ", " + viewModel.startDate.formatted(date: .omitted, time: .shortened), chevron: "chevron.right")
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsDatePopover) {
            MeetingDateTimePopover(date: startBinding)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var repeatRow: some View {
        Menu {
            Button { viewModel.recurrence = nil } label: { checkLabel("Never", viewModel.recurrence == nil) }
            ForEach(MeetingRecurrence.presets, id: \.self) { option in
                Button { viewModel.recurrence = option } label: { checkLabel(option.title, viewModel.recurrence == option) }
            }
            Divider()
            Button("Custom\u{2026}") { showsCustomRepeat = true }
        } label: {
            rowLabel("Repeat", value: MeetingRecurrence.title(for: viewModel.recurrence), chevron: "chevron.up.chevron.down")
        }
        .buttonStyle(.plain)
    }

    private var agendaRow: some View {
        Button { showsAgendaSheet = true } label: {
            rowLabel("Agenda", value: agendaPreview, chevron: "chevron.right")
        }
        .buttonStyle(.plain)
    }

    private var agendaPreview: String {
        let firstLine = viewModel.agendaText
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? ""
        return firstLine.isEmpty ? "Add agenda" : firstLine
    }

    private var calendarRow: some View {
        NavigationLink {
            AppleCalendarAccessView()
        } label: {
            rowLabel("Apple Calendar", value: viewModel.calendarService.isConnected ? "On" : "Off", chevron: "chevron.right")
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(_ title: String, value: String, chevron: String) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(PrepStyle.secondaryText)
                .lineLimit(1)
            Image(systemName: chevron)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
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

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PrepSectionLabel(text: "People")
                Spacer()
                Button("Edit") { showsPeople = true }
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
                Button("Add People") { showsPeople = true }
                    .foregroundStyle(Theme.Colors.manentAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }

    // MARK: Series

    private struct SeriesOption: Identifiable {
        let id: UUID
        let name: String
    }

    private var seriesOptions: [SeriesOption] {
        var seen = Set<UUID>()
        var result: [SeriesOption] = []
        for meeting in meetings {
            guard let id = meeting.seriesID, let name = meeting.seriesName, !name.isEmpty else { continue }
            if seen.insert(id).inserted { result.append(SeriesOption(id: id, name: name)) }
        }
        if let id = viewModel.scheduledSeriesID, !seen.contains(id) {
            result.append(SeriesOption(id: id, name: viewModel.scheduledSeriesName ?? "Series"))
        }
        return result
    }

    private var showsSeriesRow: Bool {
        !seriesOptions.isEmpty || viewModel.scheduledSeriesID != nil
    }

    private var seriesRow: some View {
        Menu {
            Button { selectSeries(nil, nil) } label: { checkLabel("None", viewModel.scheduledSeriesID == nil) }
            ForEach(seriesOptions) { option in
                Button { selectSeries(option.id, option.name) } label: {
                    checkLabel(option.name, viewModel.scheduledSeriesID == option.id)
                }
            }
            Divider()
            Button("New Series\u{2026}") {
                seriesNameDraft = ""
                showsNewSeries = true
            }
            if viewModel.scheduledSeriesID != nil {
                Button("Rename Series\u{2026}") {
                    seriesNameDraft = viewModel.scheduledSeriesName ?? ""
                    showsRenameSeries = true
                }
                Button("View Series") { showsSeries = true }
            }
        } label: {
            rowLabel("Series", value: viewModel.scheduledSeriesName ?? "None", chevron: "chevron.up.chevron.down")
        }
        .buttonStyle(.plain)
    }

    private func selectSeries(_ id: UUID?, _ name: String?) {
        viewModel.scheduledSeriesID = id
        viewModel.scheduledSeriesName = name
    }

    private func createSeries() {
        let name = seriesNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        selectSeries(UUID(), name)
    }

    private func renameSeries() {
        let name = seriesNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let id = viewModel.scheduledSeriesID else { return }
        viewModel.scheduledSeriesName = name
        for meeting in meetings where meeting.seriesID == id {
            meeting.seriesName = name
        }
        try? modelContext.save()
    }

    // MARK: Follow-up

    @ViewBuilder
    private var followUpBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            PrepSectionLabel(text: "Title")
            PrepCard {
                TextField("Title", text: $viewModel.title)
                    .fontWeight(.medium)
                    .padding(16)
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            PrepSectionLabel(text: "Agenda")
            PrepCard {
                TextField("Add Point", text: $viewModel.agendaText, axis: .vertical)
                    .lineLimit(3...10)
                    .padding(16)
            }
        }
        PrepCard {
            HStack {
                Text("Starts")
                Spacer()
                PrepDatePill(kind: .date, date: startBinding)
                PrepDatePill(kind: .time, date: startBinding)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            Divider().padding(.leading, 16)
            HStack {
                Text("Ends")
                Spacer()
                PrepDatePill(kind: .date, date: $viewModel.endDate)
                PrepDatePill(kind: .time, date: $viewModel.endDate)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
        }
        if let error = viewModel.dateValidationError {
            Text(error).font(.footnote).foregroundStyle(Theme.Colors.coralRed).padding(.horizontal, 16)
        }
        PrepCard {
            Button { showsPeople = true } label: {
                rowLabel("Participants", value: peopleCountText, chevron: "chevron.right")
            }
            .buttonStyle(.plain)
        }
        VStack(alignment: .leading, spacing: 8) {
            PrepCard {
                Toggle("Carry Over Open Actions", isOn: $viewModel.carryOverOpenActions)
                    .tint(.green)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
            }
            Text(viewModel.carryOverFootnote)
                .font(.footnote)
                .foregroundStyle(PrepStyle.secondaryText)
                .padding(.horizontal, 16)
        }
    }

    private var peopleCountText: String {
        let count = viewModel.participants.count
        return count == 1 ? "1 Person" : "\(count) People"
    }

    // MARK: Actions

    private func requestClose() {
        if viewModel.hasUnsavedChanges {
            showsDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
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

/// Calendar plus numeric time entry shown from the Date & Time row.
struct MeetingDateTimePopover: View {
    @Binding var date: Date
    @State private var editingTime = false

    var body: some View {
        VStack(spacing: 8) {
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(Theme.Colors.manentAccent)
            Divider()
            if editingTime {
                PrepTimeEntryView(date: $date) { editingTime = false }
            } else {
                HStack {
                    Text("Time")
                    Spacer()
                    Button {
                        editingTime = true
                    } label: {
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .padding(12)
        .frame(width: 340)
    }
}

/// Custom repeat interval ("Custom\u{2026}" in the Repeat menu).
struct CustomRepeatSheet: View {
    @Binding var recurrence: MeetingRecurrence?
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
