import Foundation
import SwiftData
import OfflineEngineKit

// MARK: - Pending action

/// Something Vidur understood and wants the user to confirm before it changes any data.
struct VidurPendingAction: Identifiable {
    enum Kind {
        case schedule(VidurScheduleDraft)
        case addAction(VidurActionDraft, meetingID: UUID, meetingTitle: String)
        case completeAction(actionID: UUID, title: String, meetingTitle: String)
        case setImportant(meetingID: UUID, title: String, important: Bool)
        case startRecording
    }

    let id = UUID()
    var kind: Kind
}

enum VidurPendingState: Equatable {
    case awaiting, done, cancelled
}

/// What Vidur does with a parsed command before anything is changed.
enum VidurPrepared {
    case confirm(VidurPendingAction, intro: String)
    case openMeeting(id: UUID, title: String)
    case openScreen(VidurScreen)
    case message(String)
}

/// What happened when the user confirmed an action. Never reports success that did not happen.
struct VidurActionResult {
    var message: String
    var succeeded: Bool
    /// The meeting to link to ("Open Design review").
    var meetingID: UUID?
    var meetingTitle: String?
    /// Set when a quick recording was created and the recorder should open.
    var recordingMeetingID: UUID?
    var opensActions = false
}

// MARK: - Actions

/// Runs Vidur's commands with the same app code the manual screens use. Everything stays on this iPhone.
@MainActor
enum VidurActions {
    // MARK: Context for conversation and suggestions

    static func assistantContext(modelContext: ModelContext, userName: String?, selfNames: [String], isRecording: Bool,
                                 now: Date = Date(), calendar: Calendar = .current) -> VidurAssistantContext {
        let meetings = (try? modelContext.fetch(FetchDescriptor<Meeting>())) ?? []
        let actions = (try? modelContext.fetch(FetchDescriptor<ActionItem>())) ?? []

        let upcoming = meetings
            .filter { $0.status == .scheduled && start($0) >= now }
            .sorted { start($0) < start($1) }
        let today = upcoming
            .filter { calendar.isDate(start($0), inSameDayAs: now) }
            .map { VidurMeetingBrief(title: $0.title, start: start($0)) }
        let next = upcoming.first.map { VidurMeetingBrief(title: $0.title, start: start($0)) }

        let completed = meetings
            .filter { $0.status == .completed && start($0) <= now }
            .sorted { start($0) > start($1) }
        let last = completed.first
        var hasHistory = false
        if let nextTitle = next?.title.lowercased() {
            hasHistory = completed.contains { meeting in
                meeting.title.lowercased() == nextTitle && (meeting.summary != nil || !meeting.transcriptSegments.isEmpty)
            }
        }

        let mine = Set(selfNames.map { $0.lowercased() })
        let myFirstNames = Set(selfNames.compactMap { $0.split(separator: " ").first.map { String($0).lowercased() } })
        func isMine(_ action: ActionItem) -> Bool {
            guard let name = action.assignee?.name.lowercased(), !name.isEmpty else { return true }
            if mine.contains(name) { return true }
            guard let first = name.split(separator: " ").first.map({ String($0) }) else { return false }
            return myFirstNames.contains(first)
        }
        let open = actions.filter { !$0.isCompleted }
        let overdue = open.filter { isMine($0) && ($0.dueDate ?? .distantFuture) < now }

        // Reading saved analysis is the slow part, so only the newest few meetings are checked.
        let analysed = meetings
            .filter { $0.offlineAnalysisData != nil }
            .sorted { start($0) > start($1) }
            .prefix(6)
        var pending = 0
        for meeting in analysed { pending += meeting.pendingTaskSuggestions.count }

        var name = userName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == UserProfile.defaultLocalName { name = nil }

        return VidurAssistantContext(
            userName: name, upcomingToday: today, nextMeeting: next, nextMeetingHasHistory: hasHistory,
            overdueActionCount: overdue.count, openActionCount: open.count, unreviewedSuggestionCount: pending,
            lastMeetingTitle: last?.title, lastMeetingHasMinutes: last?.summary != nil,
            isRecording: isRecording, hasAnyMeetings: !meetings.isEmpty)
    }

    private static func start(_ meeting: Meeting) -> Date { meeting.scheduledStartTime ?? meeting.createdAt }

    // MARK: Preparing

    static func prepare(_ command: VidurCommand, current: Meeting?, modelContext: ModelContext, isRecording: Bool,
                        now: Date = Date()) -> VidurPrepared {
        let meetings = (try? modelContext.fetch(FetchDescriptor<Meeting>())) ?? []
        switch command {
        case .scheduleMeeting(let draft):
            return .confirm(VidurPendingAction(kind: .schedule(draft)),
                            intro: "Here\u{2019}s what I understood. Check it, change anything you like, then tap Schedule.")

        case .addAction(let draft):
            guard let meeting = current ?? defaultMeeting(in: meetings, now: now) else {
                return .message("Actions live inside a meeting, and you have none yet. Schedule or record one first, then I can add it.")
            }
            return .confirm(VidurPendingAction(kind: .addAction(draft, meetingID: meeting.id, meetingTitle: meeting.title)),
                            intro: "I\u{2019}ll add this action to \(meeting.title). Confirm to save it.")

        case .completeAction(let query):
            let open = ((try? modelContext.fetch(FetchDescriptor<ActionItem>())) ?? []).filter { !$0.isCompleted }
            let items = open.map { item in
                VidurNamedItem(id: item.id, title: item.title,
                               date: item.dueDate ?? item.meeting.map { start($0) } ?? now)
            }
            guard let match = VidurTitleMatcher.best(query: query, in: items, now: now),
                  let action = open.first(where: { $0.id == match.id }) else {
                return .message("I couldn\u{2019}t find an open action that matches \u{201C}\(query)\u{201D}. Try words from its title, or open the Actions tab.")
            }
            return .confirm(VidurPendingAction(kind: .completeAction(actionID: action.id, title: action.title,
                                                                      meetingTitle: action.meeting?.title ?? "your meetings")),
                            intro: "I found this open action. Mark it as done?")

        case .openMeeting(let query, let preferLast):
            guard let meeting = resolveMeeting(query: query, preferLast: preferLast, current: current, meetings: meetings, now: now) else {
                return .message(query.isEmpty ? "You have no meetings to open yet."
                                : "I couldn\u{2019}t find a meeting that matches \u{201C}\(query)\u{201D}.")
            }
            return .openMeeting(id: meeting.id, title: meeting.title)

        case .startRecording:
            if isRecording { return .message("A recording is already running, so I can\u{2019}t start another one.") }
            return .confirm(VidurPendingAction(kind: .startRecording),
                            intro: "I\u{2019}ll open the recorder and start a quick meeting. Nothing leaves your iPhone.")

        case .setImportant(let query, let preferLast, let important):
            guard let meeting = resolveMeeting(query: query, preferLast: preferLast, current: current, meetings: meetings, now: now) else {
                return .message(query.isEmpty ? "You have no meetings yet."
                                : "I couldn\u{2019}t find a meeting that matches \u{201C}\(query)\u{201D}.")
            }
            return .confirm(VidurPendingAction(kind: .setImportant(meetingID: meeting.id, title: meeting.title, important: important)),
                            intro: important ? "I\u{2019}ll star this meeting." : "I\u{2019}ll remove the star from this meeting.")

        case .openScreen(let screen):
            return .openScreen(screen)
        }
    }

    private static func defaultMeeting(in meetings: [Meeting], now: Date) -> Meeting? {
        let upcoming = meetings.filter { $0.status == .scheduled && start($0) >= now }.min { start($0) < start($1) }
        return upcoming ?? meetings.max { start($0) < start($1) }
    }

    private static func resolveMeeting(query: String, preferLast: Bool, current: Meeting?, meetings: [Meeting],
                                       now: Date) -> Meeting? {
        if query.isEmpty, !preferLast, let current { return current }
        let items = meetings.map { VidurNamedItem(id: $0.id, title: $0.title, date: start($0)) }
        guard let match = VidurTitleMatcher.best(query: query, in: items, preferLast: preferLast, now: now) else { return nil }
        return meetings.first { $0.id == match.id }
    }

    // MARK: Performing

    static func perform(_ action: VidurPendingAction, modelContext: ModelContext) -> VidurActionResult {
        switch action.kind {
        case .schedule(let draft):
            return schedule(draft, modelContext: modelContext)
        case .addAction(let draft, let meetingID, _):
            return addAction(draft, meetingID: meetingID, modelContext: modelContext)
        case .completeAction(let actionID, _, _):
            return complete(actionID: actionID, modelContext: modelContext)
        case .setImportant(let meetingID, _, let important):
            return setImportant(meetingID: meetingID, important: important, modelContext: modelContext)
        case .startRecording:
            return startRecording(modelContext: modelContext)
        }
    }

    nonisolated static func describe(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    private static func recurrence(_ rule: VidurRepeat?) -> MeetingRecurrence? {
        switch rule {
        case .some(.daily): return .daily
        case .some(.weekly): return .weekly
        case .some(.biweekly): return .biweekly
        case .some(.monthly): return .monthly
        case .none: return nil
        }
    }

    /// An existing person by exact name, or by first name when only one person has it.
    private static func matchSpeaker(_ name: String, in speakers: [Speaker]) -> Speaker? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        if let exact = speakers.first(where: { $0.name.lowercased() == wanted }) { return exact }
        let firstNameMatches = speakers.filter { $0.name.lowercased().hasPrefix(wanted + " ") }
        return firstNameMatches.count == 1 ? firstNameMatches[0] : nil
    }

    /// Creates the meeting through `MeetingSetupViewModel`, the same code the Schedule screen uses,
    /// so recurrence and Apple Calendar sync behave identically.
    private static func schedule(_ draft: VidurScheduleDraft, modelContext: ModelContext) -> VidurActionResult {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.durationMinutes > 0 else {
            return VidurActionResult(message: "The meeting needs a length longer than zero minutes.", succeeded: false)
        }
        let setup = MeetingSetupViewModel(modelContext: modelContext)
        setup.title = title.isEmpty ? "Meeting" : title
        setup.startDate = draft.start
        setup.endDate = draft.end
        setup.recurrence = recurrence(draft.repeatRule)
        let known = (try? modelContext.fetch(FetchDescriptor<Speaker>())) ?? []
        for name in draft.people {
            if let speaker = matchSpeaker(name, in: known) {
                setup.addParticipant(speaker)
            } else {
                setup.addParticipant(name: name)
            }
        }
        do {
            let meeting = try setup.saveScheduledMeeting()
            var message = "Scheduled \(meeting.title) for \(describe(draft.start))"
            if !draft.people.isEmpty { message += " with " + draft.people.joined(separator: ", ") }
            if let rule = draft.repeatRule { message += ", repeating \(rule.title)" }
            message += "."
            if let note = setup.calendarSyncMessage { message += " " + note }
            return VidurActionResult(message: message, succeeded: true, meetingID: meeting.id, meetingTitle: meeting.title)
        } catch {
            return VidurActionResult(message: "I couldn\u{2019}t schedule that: \(error.localizedDescription)", succeeded: false)
        }
    }

    private static func fetchMeeting(_ id: UUID, in modelContext: ModelContext) -> Meeting? {
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private static func addAction(_ draft: VidurActionDraft, meetingID: UUID, modelContext: ModelContext) -> VidurActionResult {
        guard let meeting = fetchMeeting(meetingID, in: modelContext) else {
            return VidurActionResult(message: "That meeting is no longer there, so I didn\u{2019}t add the action.", succeeded: false)
        }
        let speakers = (try? modelContext.fetch(FetchDescriptor<Speaker>())) ?? []
        var owner: Speaker?
        if let name = draft.assignee, !name.isEmpty {
            if let existing = matchSpeaker(name, in: speakers) {
                owner = existing
            } else {
                let created = Speaker(name: name)
                modelContext.insert(created)
                owner = created
            }
        }
        do {
            let item = try MeetingRecordEditor.addAction(title: draft.title, owner: owner, dueDate: draft.due,
                                                         priority: .medium, meeting: meeting, context: modelContext)
            var message = "Added \u{201C}\(item.title)\u{201D}"
            if let name = owner?.name { message += " for \(name)" }
            if let due = draft.due { message += ", due \(describe(due))" }
            message += " in \(meeting.title)."
            return VidurActionResult(message: message, succeeded: true, meetingID: meeting.id, meetingTitle: meeting.title,
                                     opensActions: false)
        } catch {
            return VidurActionResult(message: "I couldn\u{2019}t add that action: \(error.localizedDescription)", succeeded: false)
        }
    }

    private static func complete(actionID: UUID, modelContext: ModelContext) -> VidurActionResult {
        let descriptor = FetchDescriptor<ActionItem>(predicate: #Predicate { $0.id == actionID })
        guard let item = (try? modelContext.fetch(descriptor))?.first else {
            return VidurActionResult(message: "I couldn\u{2019}t find that action any more, so nothing changed.", succeeded: false)
        }
        do {
            try MeetingRecordEditor.setCompleted(item, true, context: modelContext)
            return VidurActionResult(message: "Marked \u{201C}\(item.title)\u{201D} as done.", succeeded: true,
                                     meetingID: item.meeting?.id, meetingTitle: item.meeting?.title)
        } catch {
            return VidurActionResult(message: "I couldn\u{2019}t mark that as done: \(error.localizedDescription)", succeeded: false)
        }
    }

    private static func setImportant(meetingID: UUID, important: Bool, modelContext: ModelContext) -> VidurActionResult {
        guard let meeting = fetchMeeting(meetingID, in: modelContext) else {
            return VidurActionResult(message: "I couldn\u{2019}t find that meeting any more, so nothing changed.", succeeded: false)
        }
        let previous = meeting.isFavorite
        meeting.isFavorite = important
        do {
            try modelContext.save()
            return VidurActionResult(
                message: important ? "Starred \(meeting.title)." : "Removed the star from \(meeting.title).",
                succeeded: true, meetingID: meeting.id, meetingTitle: meeting.title)
        } catch {
            modelContext.rollback()
            meeting.isFavorite = previous
            return VidurActionResult(message: "I couldn\u{2019}t save that change: \(error.localizedDescription)", succeeded: false)
        }
    }

    /// Creates the same quick meeting the Home screen's Quick Meet button creates. The caller opens the recorder.
    private static func startRecording(modelContext: ModelContext) -> VidurActionResult {
        let meeting = Meeting(title: "Quick meeting", createdAt: Date(), duration: 0, status: .recording)
        modelContext.insert(meeting)
        do {
            try modelContext.save()
            return VidurActionResult(message: "Starting a quick recording.", succeeded: true,
                                     meetingID: meeting.id, meetingTitle: meeting.title, recordingMeetingID: meeting.id)
        } catch {
            modelContext.rollback()
            return VidurActionResult(message: "I couldn\u{2019}t start the recording: \(error.localizedDescription)", succeeded: false)
        }
    }
}
