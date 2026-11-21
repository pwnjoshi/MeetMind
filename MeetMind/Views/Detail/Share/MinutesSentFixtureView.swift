import SwiftUI
import SwiftData

#if targetEnvironment(simulator)
/// Simulator-only visual fixture for `--ui-minutes-sent`. It renders the settled "Minutes Sent" screen with sample public data.
struct MinutesSentFixtureView: View {
    @MainActor private static var store: ModelContainer?
    @MainActor private static var meeting: Meeting?

    private static let recipients: [SharedMinutesRecipient] = [
        SharedMinutesRecipient(name: "Pawan Joshi", email: "pawan@studio.example", colorHex: "#FF9500"),
        SharedMinutesRecipient(name: "Vaishnavi Shukla", email: "vaishnavi@studio.example", colorHex: "#FF2D55"),
        SharedMinutesRecipient(name: "Aaditya Uniyal", email: "aaditya@studio.example", colorHex: "#34C759"),
        SharedMinutesRecipient(name: "Garima Pant", email: "garima@studio.example", colorHex: "#AF52DE")
    ]

    @MainActor private static func prepare() -> ModelContainer {
        if let store { return store }
        let container = try! ModelContainerFactory.createInMemoryContainer()
        let sample = Meeting(title: "October planning", createdAt: Date(timeIntervalSince1970: 1791979200),
                             duration: 948, status: .completed)
        container.mainContext.insert(sample)
        sample.seriesID = UUID()
        sample.seriesName = "Product planning"
        for person in recipients {
            sample.addParticipant(Speaker(name: person.name, email: person.email, avatarColorHex: person.colorHex))
        }
        sample.addActionItem(ActionItem(title: "Send estimate", meeting: sample))
        try? container.mainContext.save()
        store = container
        meeting = sample
        return container
    }

    var body: some View {
        let container = Self.prepare()
        let state = MinutesSentState.make(outcome: .mailSent, recipients: Self.recipients)
        let entry = SharedMinutesEntry(
            channel: .mail, recipients: Self.recipients, subject: "October planning",
            bodyText: "Summary:\nLaunch timing and budget\n\nDecisions:\nBudget approval awaits the Finance estimate.")
        return NavigationStack {
            if let state {
                MinutesSentView(state: state, entry: entry, meeting: Self.meeting, onBackToMeetings: {})
            }
        }
        .modelContainer(container)
    }
}
#endif
