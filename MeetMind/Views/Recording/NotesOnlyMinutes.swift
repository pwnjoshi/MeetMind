import Foundation
import SwiftData

/// One action typed on the Notes Only screen.
public struct NotesOnlyActionDraft: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var owner: String
    public var dueDate: Date?

    public init(id: UUID = UUID(), title: String, owner: String = "", dueDate: Date? = nil) {
        self.id = id
        self.title = title
        self.owner = owner
        self.dueDate = dueDate
    }
}

/// Everything the user typed on the Notes Only screen. There is no audio and no
/// timestamps; these notes are the only source of the minutes.
public struct NotesOnlyDraft: Equatable, Sendable {
    public var discussion: String
    public var decisions: [String]
    public var actions: [NotesOnlyActionDraft]

    public init(discussion: String = "", decisions: [String] = [], actions: [NotesOnlyActionDraft] = []) {
        self.discussion = discussion
        self.decisions = decisions
        self.actions = actions
    }

    public var cleanedDiscussion: String {
        discussion.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var cleanedDecisions: [String] {
        decisions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public var cleanedActions: [NotesOnlyActionDraft] {
        actions.compactMap { action in
            let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            var copy = action
            copy.title = title
            copy.owner = action.owner.trimmingCharacters(in: .whitespacesAndNewlines)
            return copy
        }
    }

    public var hasContent: Bool {
        !cleanedDiscussion.isEmpty || !cleanedDecisions.isEmpty || !cleanedActions.isEmpty
    }
}

public enum NotesOnlyMinutesError: LocalizedError, Equatable, Sendable {
    case emptyNotes

    public var errorDescription: String? {
        switch self {
        case .emptyNotes:
            return "Write a discussion note, a decision or an action before reviewing the minutes."
        }
    }
}

/// Turns typed notes into a meeting without audio. Deterministic: the same notes
/// always produce the same summary lines, decisions and actions. The summary is
/// stored as a draft (`minutesNeedFinalization == true`) so the user still
/// finalizes the minutes.
@MainActor
public enum NotesOnlyMinutesBuilder {
    public static let modelVersion = MinutesReviewContentSnapshot.typedNotesModelVersion
    public static let defaultTitle = "Quick meeting"

    /// Paragraphs: one per non-empty line, with list markers removed.
    public static func discussionParagraphs(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { stripMarker($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    /// Summary key points: each paragraph split into sentences.
    public static func discussionPoints(from text: String) -> [String] {
        var points: [String] = []
        for paragraph in discussionParagraphs(from: text) {
            var sentences: [String] = []
            paragraph.enumerateSubstrings(in: paragraph.startIndex..<paragraph.endIndex, options: .bySentences) { substring, _, _, _ in
                if let substring {
                    let trimmed = substring.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { sentences.append(trimmed) }
                }
            }
            points.append(contentsOf: sentences.isEmpty ? [paragraph] : sentences)
        }
        return points
    }

    private static func stripMarker(_ line: String) -> String {
        var result = line
        for marker in ["- ", "\u{2022} ", "* "] where result.hasPrefix(marker) {
            result = String(result.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        return result
    }

    /// Creates (or completes) a meeting from the draft and saves it.
    /// - Parameters:
    ///   - existingMeeting: A meeting that already exists, for example one whose
    ///     recording could not start. When nil a new meeting is inserted.
    @discardableResult
    public static func save(
        draft: NotesOnlyDraft,
        title: String = defaultTitle,
        existingMeeting: Meeting? = nil,
        context: ModelContext,
        now: Date = Date()
    ) throws -> Meeting {
        guard draft.hasContent else { throw NotesOnlyMinutesError.emptyNotes }

        let paragraphs = discussionParagraphs(from: draft.cleanedDiscussion)
        let points = discussionPoints(from: draft.cleanedDiscussion)
        let decisions = draft.cleanedDecisions
        let actions = draft.cleanedActions

        let meeting: Meeting
        if let existingMeeting {
            meeting = existingMeeting
        } else {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            meeting = Meeting(
                title: trimmedTitle.isEmpty ? defaultTitle : trimmedTitle,
                createdAt: now,
                duration: 0,
                status: .completed
            )
            context.insert(meeting)
        }

        meeting.status = .completed
        meeting.duration = 0
        meeting.minutesNeedFinalization = true

        for paragraph in paragraphs {
            let note = Note(content: paragraph, timestamp: 0, createdAt: now)
            context.insert(note)
            meeting.addNote(note)
        }
        for decision in decisions {
            let note = Note(content: "Decision: \(decision)", timestamp: 0, createdAt: now)
            context.insert(note)
            meeting.addNote(note)
        }

        let executiveSummary: String
        if !points.isEmpty {
            executiveSummary = points.joined(separator: " ")
        } else if !decisions.isEmpty {
            executiveSummary = decisions.joined(separator: " ")
        } else {
            executiveSummary = actions.map(\.title).joined(separator: " ")
        }
        if let summary = meeting.summary {
            summary.executiveSummary = executiveSummary
            summary.keyPoints = points
            summary.keyDecisions = decisions
            summary.generatedAt = now
            summary.modelVersion = modelVersion
        } else {
            let summary = Summary(
                executiveSummary: executiveSummary,
                keyPoints: points,
                keyDecisions: decisions,
                generatedAt: now,
                modelVersion: modelVersion
            )
            context.insert(summary)
            meeting.summary = summary
        }

        for action in actions {
            var assignee: Speaker?
            if !action.owner.isEmpty {
                if let existing = meeting.participants.first(where: { $0.name == action.owner }) {
                    assignee = existing
                } else {
                    let speaker = Speaker(name: action.owner)
                    context.insert(speaker)
                    meeting.addParticipant(speaker)
                    assignee = speaker
                }
            }
            let item = ActionItem(
                title: action.title,
                taskDescription: "",
                priority: .medium,
                dueDate: action.dueDate,
                assignee: assignee
            )
            context.insert(item)
            meeting.addActionItem(item)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return meeting
    }
}
