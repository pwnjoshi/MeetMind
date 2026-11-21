import Foundation

// MARK: - Meeting type

enum MinutesMeetingType: String, Codable, CaseIterable, Sendable, Identifiable {
    case teamProject
    case officeDepartment
    case society
    case boardOfDirectors
    case boardCommittee
    case generalMeeting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .teamProject: return "Team / Project"
        case .officeDepartment: return "Office / Department"
        case .society: return "Society / RWA / Trust"
        case .boardOfDirectors: return "Board of Directors"
        case .boardCommittee: return "Board Committee"
        case .generalMeeting: return "General Meeting · AGM / EGM"
        }
    }

    var subtitle: String {
        switch self {
        case .teamProject: return "Internal meetings and project reviews"
        case .officeDepartment: return "Department reviews and follow-up"
        case .society: return "Managing committees and office bearers"
        case .boardOfDirectors: return "Board meetings"
        case .boardCommittee: return "Audit, CSR and other Board committees"
        case .generalMeeting: return "Annual or extraordinary general meetings"
        }
    }

    /// Built-in template suggested for this meeting type.
    var suggestedTemplate: MinutesBuiltInTemplate {
        switch self {
        case .teamProject: return .projectReview
        case .officeDepartment: return .departmentFollowUp
        case .society, .boardCommittee: return .societyCommittee
        case .boardOfDirectors: return .boardProceedings
        case .generalMeeting: return .generalMeeting
        }
    }
}

// MARK: - Format

enum MinutesFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    case corporateStandard
    case briefNote
    case officeActionRecord

    var id: String { rawValue }

    var title: String {
        switch self {
        case .corporateStandard: return "Corporate standard"
        case .briefNote: return "Brief note"
        case .officeActionRecord: return "Office action record"
        }
    }

    var subtitle: String {
        switch self {
        case .corporateStandard: return "Agenda, decision and action"
        case .briefNote: return "Concise outcomes and next steps"
        case .officeActionRecord: return "Numbered directions with owner and deadline"
        }
    }
}

// MARK: - Sections

enum MinutesSection: String, Codable, CaseIterable, Sendable, Identifiable {
    case attendance
    case absences
    case previousMinutes
    case discussion
    case decisions
    case actionItems
    case nextMeeting
    case signature
    case participantNames

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attendance: return "Attendance"
        case .absences: return "Absences and leave"
        case .previousMinutes: return "Previous minutes"
        case .discussion: return "Discussion summary"
        case .decisions: return "Decisions"
        case .actionItems: return "Action items"
        case .nextMeeting: return "Next meeting"
        case .signature: return "Signature block"
        case .participantNames: return "Participant names"
        }
    }

    static let standardEnabled: [MinutesSection] = [
        .attendance, .absences, .discussion, .decisions, .actionItems, .participantNames
    ]
}

// MARK: - Attendance

enum MinutesAttendanceStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case unconfirmed
    case presentInPerson
    case presentByVideo
    case apologyReceived
    case absent
    case leaveGranted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unconfirmed: return "Unconfirmed"
        case .presentInPerson: return "Present in Person"
        case .presentByVideo: return "Present by Video"
        case .apologyReceived: return "Apology Received"
        case .absent: return "Absent"
        case .leaveGranted: return "Leave Granted"
        }
    }

    var subtitle: String {
        switch self {
        case .unconfirmed: return "Keep this person pending"
        case .presentInPerson: return "Attended in the room"
        case .presentByVideo: return "Attended remotely"
        case .apologyReceived: return "Sent an apology"
        case .absent: return "Confirmed they did not attend"
        case .leaveGranted: return "Leave was formally granted"
        }
    }

    /// Lower-case wording used inside the document, e.g. "Present in person".
    var documentLabel: String {
        switch self {
        case .unconfirmed: return "Unconfirmed"
        case .presentInPerson: return "Present in person"
        case .presentByVideo: return "Present by video"
        case .apologyReceived: return "Apology received"
        case .absent: return "Absent"
        case .leaveGranted: return "Leave granted"
        }
    }

    var isPresent: Bool { self == .presentInPerson || self == .presentByVideo }

    var isAbsence: Bool { self == .apologyReceived || self == .absent || self == .leaveGranted }

    var isConfirmed: Bool { self != .unconfirmed }
}

// MARK: - Built-in templates and letterheads

enum MinutesBuiltInTemplate: String, Codable, CaseIterable, Sendable, Identifiable {
    case projectReview
    case departmentFollowUp
    case societyCommittee
    case boardProceedings
    case generalMeeting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projectReview: return "Project review"
        case .departmentFollowUp: return "Department follow-up"
        case .societyCommittee: return "Society committee"
        case .boardProceedings: return "Board proceedings"
        case .generalMeeting: return "General meeting"
        }
    }

    var subtitle: String {
        switch self {
        case .projectReview: return "Agenda, decisions and action owners"
        case .departmentFollowUp: return "Directions, responsibilities and deadlines"
        case .societyCommittee: return "Attendance, decisions and a signature block"
        case .boardProceedings: return "SS-1 structure for applicable meetings"
        case .generalMeeting: return "SS-2 structure for applicable AGM or EGM"
        }
    }

    var documentHeading: String {
        switch self {
        case .projectReview: return "Minutes of meeting"
        case .departmentFollowUp: return "Record of directions"
        case .societyCommittee: return "Minutes of committee meeting"
        case .boardProceedings: return "Minutes of the Board meeting"
        case .generalMeeting: return "Minutes of the general meeting"
        }
    }

    var defaultFormat: MinutesFormat {
        switch self {
        case .departmentFollowUp: return .officeActionRecord
        default: return .corporateStandard
        }
    }

    var defaultSections: [MinutesSection] {
        switch self {
        case .projectReview:
            return MinutesSection.standardEnabled
        case .departmentFollowUp:
            return [.attendance, .absences, .decisions, .actionItems, .participantNames]
        case .societyCommittee:
            return MinutesSection.standardEnabled + [.signature]
        case .boardProceedings, .generalMeeting:
            return MinutesSection.standardEnabled + [.previousMinutes, .nextMeeting, .signature]
        }
    }
}

enum MinutesBuiltInLetterhead: String, Codable, CaseIterable, Sendable, Identifiable {
    case plain
    case company
    case office
    case society

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: return "Plain"
        case .company: return "Company"
        case .office: return "Office"
        case .society: return "Society / Trust"
        }
    }

    var subtitle: String {
        switch self {
        case .plain: return "No document header"
        case .company: return "Company name and registered office"
        case .office: return "Centred department header"
        case .society: return "Society or trust name"
        }
    }

    var isCentered: Bool { self == .office || self == .society }
}

// MARK: - Configuration

/// Per-meeting Minutes Studio selections. Template and letterhead ids are either a
/// built-in raw value or the UUID string of a user-saved item.
struct MinutesStudioConfig: Codable, Equatable, Sendable {
    var meetingType: MinutesMeetingType
    var templateID: String
    var format: MinutesFormat
    var letterheadID: String
    var organisationName: String
    var organisationAddress: String
    var enabledSections: [MinutesSection]
    var sectionOrder: [MinutesSection]
    /// Keyed by participant UUID string.
    var attendance: [String: MinutesAttendanceStatus]

    static func standard() -> MinutesStudioConfig {
        let template = MinutesBuiltInTemplate.projectReview
        return MinutesStudioConfig(
            meetingType: .teamProject,
            templateID: template.rawValue,
            format: template.defaultFormat,
            letterheadID: MinutesBuiltInLetterhead.plain.rawValue,
            organisationName: "",
            organisationAddress: "",
            enabledSections: template.defaultSections,
            sectionOrder: MinutesSection.allCases,
            attendance: [:]
        )
    }

    func isEnabled(_ section: MinutesSection) -> Bool {
        enabledSections.contains(section)
    }

    mutating func setEnabled(_ section: MinutesSection, _ enabled: Bool) {
        if enabled {
            if !enabledSections.contains(section) { enabledSections.append(section) }
        } else {
            enabledSections.removeAll { $0 == section }
        }
    }

    /// Enabled sections in the user's chosen order. Sections missing from the saved
    /// order are appended in canonical order so old files never lose sections.
    var orderedEnabledSections: [MinutesSection] {
        var ordered = sectionOrder
        for section in MinutesSection.allCases where !ordered.contains(section) {
            ordered.append(section)
        }
        return ordered.filter { enabledSections.contains($0) }
    }

    /// Applies a template's defaults (format and contents), keeping letterhead and attendance.
    mutating func applyTemplate(id: String, format: MinutesFormat, sections: [MinutesSection]) {
        templateID = id
        self.format = format
        enabledSections = sections
    }
}

// MARK: - User-saved library items

struct MinutesCustomTemplate: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case savedSetup
        case importedPDF
    }

    var id: UUID
    var name: String
    var kind: Kind
    var createdAt: Date
    var meetingType: MinutesMeetingType
    var format: MinutesFormat
    var enabledSections: [MinutesSection]
    var sectionOrder: [MinutesSection]
    var letterheadID: String?
    /// File name inside the store's Templates folder for imported PDFs.
    var pdfFileName: String?

    var subtitle: String {
        switch kind {
        case .savedSetup: return "Saved setup · \(format.title)"
        case .importedPDF: return "Imported PDF · \(format.title) structure"
        }
    }
}

struct MinutesCustomLetterhead: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    /// File name inside the store's Letterheads folder.
    var fileName: String
    var isPDF: Bool
}

struct MinutesStudioLibrary: Codable, Equatable, Sendable {
    var templates: [MinutesCustomTemplate]
    var letterheads: [MinutesCustomLetterhead]

    static let empty = MinutesStudioLibrary(templates: [], letterheads: [])
}

struct MinutesStudioConfigFile: Codable, Equatable, Sendable {
    /// Keyed by meeting UUID string.
    var configs: [String: MinutesStudioConfig]
}
