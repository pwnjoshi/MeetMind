import Foundation

enum MoMStatusKind: Equatable, Sendable {
    case draft
    case finalized
    case signed

    var text: String {
        switch self {
        case .draft: return "Draft \u{00B7} Review before sharing"
        case .finalized: return "Finalized"
        case .signed: return "Signed"
        }
    }
}

/// One reviewed Minutes of Meeting document. The screen, the PDF and the share text all render this value.
struct MoMDocumentModel: Equatable, Sendable {
    struct PersonRow: Equatable, Identifiable, Sendable {
        var id: String
        var name: String
        var initials: String
        var colorHex: String
        var trailing: String
        var isLeaveGranted: Bool = false
    }

    struct ActionRow: Equatable, Identifiable, Sendable {
        var id: String
        var number: Int
        var title: String
        var by: String
        var target: String
        var isDone: Bool
    }

    struct PreviousMinutes: Equatable, Sendable {
        var text: String
        var meetingID: UUID?
        var linkTitle: String?
    }

    struct SignOff: Equatable, Sendable {
        var name: String
        var role: String
        var signaturePNG: Data?
        var signedAt: Date?
        var place: String?
        var recordedBy: String
    }

    var reference: String
    var title: String
    var subtitle: String
    var status: MoMStatusKind
    var styleTitle: String
    var dateText: String
    var timeText: String
    var venue: String?
    var chairperson: String?
    var minutesBy: String?
    var quorumText: String?
    var quorumMet: Bool
    var present: [PersonRow]
    var invitees: [PersonRow]
    var leave: [PersonRow]
    var previous: PreviousMinutes
    var topics: [MoMTopic]
    var actions: [ActionRow]
    var anyOtherBusiness: String
    var nextMeetingText: String?
    var nextMeetingNote: String?
    var closure: String
    var signOff: SignOff
    var mentionedPeople: [MoMSuggestedAttendee]

    static let sectionTitles: [(id: String, title: String)] = [
        ("attendance", "Attendance"), ("agenda", "Agenda"), ("decisions", "Decisions"), ("actions", "Action Taken")
    ]

    /// Plain text of the whole document. Used as the body of Mail and the share sheet.
    var plainText: String {
        var lines: [String] = ["MINUTES OF MEETING", reference, title]
        if !subtitle.isEmpty { lines.append(subtitle) }
        lines.append("Status: \(status.text)")
        lines.append("")
        lines.append("Date: \(dateText)")
        lines.append("Time: \(timeText)")
        if let venue, !venue.isEmpty { lines.append("Venue: \(venue)") }
        if let chairperson { lines.append("Chairperson: \(chairperson)") }
        if let minutesBy { lines.append("Minutes by: \(minutesBy)") }

        lines.append("")
        lines.append("1. Attendance")
        if let quorumText { lines.append(quorumText) }
        if !present.isEmpty { lines.append("Present:") }
        for row in present { lines.append("  \(row.name) (\(row.trailing))") }
        if !invitees.isEmpty { lines.append("In attendance (invitee):") }
        for row in invitees { lines.append("  \(row.name) (\(row.trailing))") }
        if !leave.isEmpty { lines.append("Leave of absence:") }
        for row in leave { lines.append("  \(row.name) (\(row.trailing))") }

        lines.append("")
        lines.append("2. Previous Minutes")
        lines.append(previous.text)

        lines.append("")
        lines.append("3. Agenda and Discussion")
        for (index, topic) in topics.enumerated() {
            lines.append("3.\(index + 1) \(topic.title)")
            for bullet in topic.discussion { lines.append("  - \(bullet)") }
            if topic.hasOutcome {
                var line = "  \(topic.outcomeKind.label): \(topic.outcomeText)"
                if let chip = topic.sourceChipText { line += " [\(chip)]" }
                lines.append(line)
            }
        }

        lines.append("")
        lines.append("4. Action Taken Report")
        if actions.isEmpty { lines.append("No actions were recorded.") }
        for row in actions {
            lines.append("  \(row.number). \(row.title) | \(row.by) | \(row.target) | \(row.isDone ? "Done" : "Open")")
        }

        lines.append("")
        lines.append("5. Any Other Business")
        lines.append(anyOtherBusiness)
        lines.append("")
        lines.append("6. Next Meeting")
        if let nextMeetingText { lines.append(nextMeetingText) }
        if let nextMeetingNote { lines.append(nextMeetingNote) }
        if nextMeetingText == nil && nextMeetingNote == nil { lines.append("Not scheduled.") }
        lines.append("")
        lines.append("7. Closure")
        lines.append(closure.isEmpty ? "Not recorded." : closure)
        lines.append("")
        lines.append("8. Sign-off")
        if status == .signed {
            var signed = "Signed by \(signOff.name), \(signOff.role)"
            if let date = signOff.signedAt { signed += " on \(MoMDocumentBuilder.longDate(date))" }
            if let place = signOff.place, !place.isEmpty { signed += " at \(place)" }
            lines.append(signed)
        } else {
            lines.append("Not yet signed. \(signOff.name), \(signOff.role)")
        }
        lines.append(signOff.recordedBy)
        return lines.joined(separator: "\n")
    }
}

@MainActor
enum MoMDocumentBuilder {
    nonisolated static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year())
    }

    nonisolated static func ordinal(_ number: Int) -> String {
        let tens = number % 100
        if tens >= 11 && tens <= 13 { return "\(number)th" }
        switch number % 10 {
        case 1: return "\(number)st"
        case 2: return "\(number)nd"
        case 3: return "\(number)rd"
        default: return "\(number)th"
        }
    }

    /// Series meetings ordered by date, used for "46th weekly meeting" and the previous-minutes link.
    static func seriesMeetings(of meeting: Meeting, in all: [Meeting]) -> [Meeting] {
        guard let seriesID = meeting.seriesID else { return [] }
        return all.filter { $0.seriesID == seriesID }
            .sorted { ($0.scheduledStartTime ?? $0.createdAt) < ($1.scheduledStartTime ?? $1.createdAt) }
    }

    static func build(meeting: Meeting,
                      record: MeetingRecordData,
                      sidecar: MoMSidecar,
                      reference: String,
                      isFinalized: Bool,
                      userName: String?,
                      seriesMeetings: [Meeting],
                      studioConfig: MinutesStudioConfig?) -> MoMDocumentModel {
        let content = MeetingMinutesContent.make(from: meeting, record: record)
        let engine = MoMEngineFields.parse(meeting.offlineAnalysisData)
        let start = meeting.scheduledStartTime ?? meeting.createdAt
        let style = sidecar.style ?? .corporateIndia

        var subtitle = ""
        var previousMeeting: Meeting?
        if let seriesName = meeting.seriesName, !seriesName.isEmpty {
            if let index = seriesMeetings.firstIndex(where: { $0.id == meeting.id }) {
                subtitle = "\(ordinal(index + 1)) \(seriesName)"
                if index > 0 { previousMeeting = seriesMeetings[index - 1] }
            } else {
                subtitle = seriesName
            }
        }
        if let folder = meeting.folder?.name, !folder.isEmpty {
            subtitle = subtitle.isEmpty ? folder : "\(subtitle) \u{00B7} \(folder)"
        }

        // People
        let inviteeIDs = Set(sidecar.inviteeIDs)
        let leaveIDs = Set(sidecar.leaveGrantedIDs)
        let chairID = sidecar.chairpersonID
        var chairName: String?
        var present: [MoMDocumentModel.PersonRow] = []
        var invitees: [MoMDocumentModel.PersonRow] = []
        var leave: [MoMDocumentModel.PersonRow] = []
        let absentIDs = Set(meeting.absentParticipantIDs ?? [])
        for speaker in meeting.namedAttendees {
            let key = speaker.id.uuidString
            let isChair = chairID == key
                || (chairID == nil && (speaker.role ?? "").lowercased().contains("chair"))
            if isChair && chairName == nil { chairName = speaker.name }
            let role = (speaker.role ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var base = isChair ? "Chairperson" : (role.isEmpty ? "Member" : role)
            if absentIDs.contains(speaker.id) {
                let granted = leaveIDs.contains(key)
                leave.append(.init(id: key, name: speaker.name, initials: speaker.initials,
                                   colorHex: speaker.avatarColorHex,
                                   trailing: granted ? "Leave granted" : "Absent", isLeaveGranted: granted))
                continue
            }
            if studioConfig?.attendance[key] == .presentByVideo { base += " \u{00B7} Video" }
            if inviteeIDs.contains(key) && !isChair {
                invitees.append(.init(id: key, name: speaker.name, initials: speaker.initials,
                                      colorHex: speaker.avatarColorHex, trailing: role.isEmpty ? "Invitee" : role))
            } else {
                present.append(.init(id: key, name: speaker.name, initials: speaker.initials,
                                     colorHex: speaker.avatarColorHex, trailing: base))
            }
        }
        // Chairperson first.
        if let chairName, let index = present.firstIndex(where: { $0.name == chairName }), index > 0 {
            present.insert(present.remove(at: index), at: 0)
        }
        let members = present.count + leave.count
        var quorumText: String?
        var quorumMet = false
        if members > 0 {
            quorumMet = present.count * 2 > members
            quorumText = quorumMet
                ? "Quorum present \u{00B7} \(present.count) of \(members) members"
                : "Quorum not met \u{00B7} \(present.count) of \(members) members"
        }

        // Previous minutes
        var previous = MoMDocumentModel.PreviousMinutes(text: "Not applicable. This is the first recorded meeting.",
                                                         meetingID: nil, linkTitle: nil)
        if let previousMeeting, previousMeeting.summary != nil {
            let when = previousMeeting.scheduledStartTime ?? previousMeeting.createdAt
            previous = .init(text: "Previous meeting: \(previousMeeting.title), held on \(longDate(when)).",
                             meetingID: previousMeeting.id, linkTitle: "Open previous meeting minutes")
        }

        // Topics
        let decisionTexts = content.decisions.map(\.text)
        let topics = MoMTopicResolver.resolve(edited: sidecar.topics, engine: engine.topics,
                                              discussion: content.discussion, decisions: decisionTexts,
                                              openIssues: content.openIssues)

        // Actions
        var actions: [MoMDocumentModel.ActionRow] = []
        for (index, line) in content.actions.enumerated() {
            let target = line.due.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "\u{2014}"
            let by = line.owner.map { MeetingRecordFormatting.firstName($0) } ?? "Unassigned"
            actions.append(.init(id: line.id.uuidString, number: index + 1, title: line.title,
                                 by: by, target: target, isDone: line.isCompleted))
        }

        // People mentioned
        let known = Set(meeting.participants.map { $0.name.lowercased() })
        let dismissed = Set(sidecar.dismissedMentions)
        let mentioned = engine.suggestedAttendees.filter {
            !known.contains($0.name.lowercased()) && !dismissed.contains($0.name.lowercased())
        }

        // Time
        var timeText = start.formatted(date: .omitted, time: .shortened)
        var endText: String?
        if meeting.duration > 0 {
            let end = start.addingTimeInterval(meeting.duration)
            endText = end.formatted(date: .omitted, time: .shortened)
            timeText += " \u{2013} \(endText ?? "")"
        }
        if let abbreviation = TimeZone.current.abbreviation() { timeText += " \(abbreviation)" }

        // Next meeting
        var nextText: String?
        var nextNote = sidecar.nextMeetingNote
        var nextDate = sidecar.nextMeetingDate
        if nextDate == nil && nextNote == nil, let hint = engine.nextMeeting {
            nextDate = hint.date
            nextNote = hint.note
        }
        if let nextDate {
            nextText = nextDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                + " \u{00B7} " + nextDate.formatted(date: .omitted, time: .shortened)
        }

        let aob = (sidecar.anyOtherBusiness ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var closure = (sidecar.closure ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if closure.isEmpty, let endText { closure = "The meeting ended at \(endText)." }

        let signer = chairName ?? "Chairperson"
        let status: MoMStatusKind = sidecar.isSigned ? .signed : (isFinalized ? .finalized : .draft)
        let recordedBy = "Recorded by \(sidecar.minutesBy ?? userName ?? "the note taker") with Manent on this iPhone."

        return MoMDocumentModel(
            reference: reference,
            title: meeting.title,
            subtitle: subtitle,
            status: status,
            styleTitle: style.shortTitle,
            dateText: start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()),
            timeText: timeText,
            venue: sidecar.venue,
            chairperson: chairName,
            minutesBy: sidecar.minutesBy ?? userName,
            quorumText: quorumText,
            quorumMet: quorumMet,
            present: present,
            invitees: invitees,
            leave: leave,
            previous: previous,
            topics: topics,
            actions: actions,
            anyOtherBusiness: aob.isEmpty ? "No other business was recorded." : aob,
            nextMeetingText: nextText,
            nextMeetingNote: nextNote,
            closure: closure,
            signOff: .init(name: sidecar.signedByName ?? signer, role: "Chairperson",
                           signaturePNG: sidecar.signaturePNG, signedAt: sidecar.signedAt,
                           place: sidecar.signedPlace, recordedBy: recordedBy),
            mentionedPeople: mentioned
        )
    }
}

@MainActor
extension MoMDocumentBuilder {
    /// The document as it is right now, with its stored reference number (created on first use).
    static func current(meeting: Meeting, allMeetings: [Meeting], userName: String?, isFinalized: Bool,
                        store: MoMSidecarStore = .shared) -> MoMDocumentModel {
        let date = meeting.scheduledStartTime ?? meeting.createdAt
        let title = meeting.seriesName ?? meeting.title
        let sidecar = store.sidecar(for: meeting.id)
        let reference = (try? store.referenceNumber(for: meeting.id, title: title, date: date))
            ?? sidecar.referenceNumber ?? MoMReference.format(title: title, year: 0, sequence: 1)
        return build(meeting: meeting, record: MeetingRecordStore.shared.record(for: meeting.id),
                     sidecar: store.sidecar(for: meeting.id), reference: reference, isFinalized: isFinalized,
                     userName: userName, seriesMeetings: seriesMeetings(of: meeting, in: allMeetings),
                     studioConfig: MinutesStudioStore.shared.config(for: meeting.id))
    }
}
