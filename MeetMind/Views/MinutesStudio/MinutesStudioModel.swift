import SwiftUI
import SwiftData
import Observation
import UIKit

/// Shared state for every Minutes Studio page of one meeting.
@MainActor
@Observable
final class MinutesStudioModel {
    let meeting: Meeting
    let store: MinutesStudioStore
    private(set) var config: MinutesStudioConfig

    @ObservationIgnored private var cachedLetterheadID: String?
    @ObservationIgnored private var cachedLetterheadImage: UIImage?

    init(meeting: Meeting, store: MinutesStudioStore = .shared) {
        self.meeting = meeting
        self.store = store
        self.config = store.config(for: meeting.id) ?? .standard()
    }

    // MARK: Derived values

    var snapshot: MinutesMeetingSnapshot { MinutesMeetingSnapshot.make(from: meeting) }

    var templateName: String { store.templateName(for: config.templateID) }

    var letterheadName: String { store.letterheadName(for: config.letterheadID) }

    var documentHeading: String {
        MinutesBuiltInTemplate(rawValue: config.templateID)?.documentHeading ?? "Minutes of meeting"
    }

    var attendanceSummary: String {
        let snapshot = self.snapshot
        let confirmed = MinutesDocumentBuilder.confirmedCount(snapshot: snapshot, config: config)
        return "\(confirmed) of \(snapshot.participants.count) confirmed"
    }

    var contentsSummary: String {
        let count = config.enabledSections.count
        return count == 1 ? "1 section" : "\(count) sections"
    }

    var document: MinutesDocument {
        MinutesDocumentBuilder.build(
            snapshot: snapshot,
            config: config,
            templateName: templateName,
            documentHeading: documentHeading
        )
    }

    /// Every section in the user's order, including disabled ones.
    var fullSectionOrder: [MinutesSection] {
        var ordered = config.sectionOrder
        for section in MinutesSection.allCases where !ordered.contains(section) {
            ordered.append(section)
        }
        return ordered
    }

    func status(for participantID: UUID) -> MinutesAttendanceStatus {
        MinutesDocumentBuilder.status(
            for: participantID,
            config: config,
            defaultAbsentIDs: meeting.absentParticipantIDs ?? []
        )
    }

    func letterheadImage() -> UIImage? {
        if cachedLetterheadID == config.letterheadID, cachedLetterheadImage != nil {
            return cachedLetterheadImage
        }
        guard let custom = store.letterhead(withID: config.letterheadID) else {
            cachedLetterheadID = config.letterheadID
            cachedLetterheadImage = nil
            return nil
        }
        let image = MinutesLetterheadLoader.image(for: custom, store: store)
        cachedLetterheadID = config.letterheadID
        cachedLetterheadImage = image
        return image
    }

    // MARK: Mutations

    func update(_ change: (inout MinutesStudioConfig) -> Void) {
        var next = config
        change(&next)
        guard next != config else { return }
        config = next
        store.save(next, for: meeting.id)
    }

    func selectMeetingType(_ type: MinutesMeetingType) {
        let suggested = type.suggestedTemplate
        let keepsCustomTemplate = store.template(withID: config.templateID) != nil
        update { value in
            value.meetingType = type
            if !keepsCustomTemplate {
                value.applyTemplate(id: suggested.rawValue, format: suggested.resolvedFormat, sections: suggested.defaultSections)
            }
        }
    }

    func selectTemplate(_ template: MinutesBuiltInTemplate) {
        update {
            $0.applyTemplate(id: template.rawValue, format: template.resolvedFormat, sections: template.defaultSections)
        }
    }

    func selectCustomTemplate(_ template: MinutesCustomTemplate) {
        let letterheadValid = template.letterheadID.map {
            MinutesBuiltInLetterhead(rawValue: $0) != nil || store.letterhead(withID: $0) != nil
        } ?? false
        update { value in
            value.applyTemplate(id: template.id.uuidString, format: template.format, sections: template.enabledSections)
            value.sectionOrder = template.sectionOrder
            value.meetingType = template.meetingType
            if let letterheadID = template.letterheadID, letterheadValid {
                value.letterheadID = letterheadID
            }
        }
    }

    func selectFormat(_ format: MinutesFormat) {
        update { $0.format = format }
    }

    func selectLetterhead(id: String) {
        update { $0.letterheadID = id }
    }

    func setSection(_ section: MinutesSection, enabled: Bool) {
        update { $0.setEnabled(section, enabled) }
    }

    func moveSections(from offsets: IndexSet, to destination: Int) {
        var order = fullSectionOrder
        order.move(fromOffsets: offsets, toOffset: destination)
        update { $0.sectionOrder = order }
    }

    /// Records the status in the studio config and mirrors absences into `Meeting.absentParticipantIDs`.
    func setAttendance(_ status: MinutesAttendanceStatus, for participantID: UUID, context: ModelContext) {
        update { $0.attendance[participantID.uuidString] = status }
        let absent = MinutesDocumentBuilder.absentIDs(snapshot: snapshot, config: config)
        let current = meeting.absentParticipantIDs ?? []
        if Set(absent) != Set(current) {
            meeting.absentParticipantIDs = absent
            try? context.save()
        }
    }

    func deleteCustomTemplate(_ template: MinutesCustomTemplate) {
        store.deleteTemplate(id: template.id)
        if config.templateID == template.id.uuidString {
            selectTemplate(.projectReview)
        }
    }

    func deleteCustomLetterhead(_ letterhead: MinutesCustomLetterhead) {
        store.deleteLetterhead(id: letterhead.id)
        if config.letterheadID == letterhead.id.uuidString {
            selectLetterhead(id: MinutesBuiltInLetterhead.plain.rawValue)
        }
    }
}

/// Drives the single-title confirmation alerts shown in the frames ("Template Saved", ...).
@MainActor
@Observable
final class MinutesAlertCenter {
    var notice: String?
    var errorText: String?

    /// Waits for a dismissing sheet or alert to finish before presenting the next alert.
    func showNotice(_ text: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            self.notice = text
        }
    }

    func showError(_ error: Error) {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            self.errorText = text
        }
    }
}

struct MinutesAlertsModifier: ViewModifier {
    let alerts: MinutesAlertCenter

    func body(content: Content) -> some View {
        content
            .alert(
                alerts.notice ?? "",
                isPresented: Binding(
                    get: { alerts.notice != nil },
                    set: { if !$0 { alerts.notice = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            }
            .alert(
                "Couldn't Complete",
                isPresented: Binding(
                    get: { alerts.errorText != nil },
                    set: { if !$0 { alerts.errorText = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alerts.errorText ?? "")
            }
    }
}

extension View {
    func minutesAlerts(_ alerts: MinutesAlertCenter) -> some View {
        modifier(MinutesAlertsModifier(alerts: alerts))
    }
}
