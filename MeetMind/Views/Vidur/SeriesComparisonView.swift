import SwiftUI
import SwiftData

/// Step 1 of the series comparison: pick two saved meetings of one series.
@MainActor
public struct SeriesComparisonView: View {
    public let seriesID: UUID
    public let seriesName: String

    @Query(sort: \Meeting.createdAt, order: .forward) private var allMeetings: [Meeting]
    @State private var fromID: UUID?
    @State private var toID: UUID?
    @State private var diff: SeriesDiff?
    @State private var showsResult = false

    public init(seriesID: UUID, seriesName: String) {
        self.seriesID = seriesID
        self.seriesName = seriesName
    }

    private var seriesMeetings: [Meeting] {
        allMeetings.filter { $0.seriesID == seriesID }
    }

    private var canCompare: Bool {
        guard let fromID, let toID else { return false }
        return fromID != toID
    }

    public var body: some View {
        VStack(spacing: 0) {
            if seriesMeetings.count < 2 {
                ContentUnavailableView(
                    "Not Enough Meetings",
                    systemImage: "rectangle.on.rectangle",
                    description: Text("A series needs at least two saved meetings before you can compare them."))
            } else {
                List {
                    Section {
                        pickerRow(title: "From", selection: $fromID)
                        pickerRow(title: "To", selection: $toID)
                    } footer: {
                        Text("Compared from saved decisions, action items, agenda and attendance. Nothing is generated.")
                    }
                }
                .listStyle(.insetGrouped)
                Button(action: compare) {
                    Text("Compare Meetings")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(Theme.Colors.manentAccent.opacity(canCompare ? 1 : 0.4), in: Capsule())
                }
                .disabled(!canCompare)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(seriesName)
        .navigationBarTitleDisplayMode(.large)
        .tint(Theme.Colors.manentAccent)
        .onAppear(perform: applyDefaults)
        .navigationDestination(isPresented: $showsResult) {
            if let diff {
                SeriesChangesView(diff: diff)
            }
        }
    }

    private func pickerRow(title: String, selection: Binding<UUID?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(seriesMeetings) { meeting in
                    Text("\(meeting.title) \u{00B7} \(Self.dateText(meeting.createdAt))").tag(Optional(meeting.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private func applyDefaults() {
        let meetings = seriesMeetings
        guard meetings.count >= 2 else { return }
        let ids = Set(meetings.map { $0.id })
        if fromID == nil || !ids.contains(fromID ?? UUID()) { fromID = meetings[meetings.count - 2].id }
        if toID == nil || !ids.contains(toID ?? UUID()) { toID = meetings[meetings.count - 1].id }
    }

    private func compare() {
        guard let first = seriesMeetings.first(where: { $0.id == fromID }),
              let second = seriesMeetings.first(where: { $0.id == toID }), first.id != second.id else { return }
        diff = SeriesDiffEngine.compare(SeriesMeetingSnapshot.make(from: first), SeriesMeetingSnapshot.make(from: second))
        showsResult = true
    }

    static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// Step 2: "What Changed" between the two chosen meetings.
@MainActor
public struct SeriesChangesView: View {
    public let diff: SeriesDiff

    @Environment(NavigationRouter.self) private var router: NavigationRouter?
    @Environment(AppState.self) private var appState: AppState?

    public init(diff: SeriesDiff) {
        self.diff = diff
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                headerChips
                Text("\(diff.changedCount) changed \u{00B7} \(diff.stillOpenCount) still open")
                    .font(.subheadline).foregroundStyle(.secondary)
                if diff.changedCount == 0 && diff.stillOpenCount == 0 {
                    card(title: "No Differences", icon: "equal.circle", badge: nil) {
                        Text("These meetings have the same saved decisions, action items, agenda and attendance.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if diff.decisionChangeCount > 0 {
                    card(title: "Decisions", icon: "checkmark.seal", badge: "Changed") {
                        group("New in \(diff.later.title)", diff.decisionsNew)
                        group("Not repeated later", diff.decisionsNotRepeated)
                    }
                }
                if diff.actionChangeCount > 0 {
                    card(title: "Action Items", icon: "checklist", badge: "Changed") {
                        group("New", diff.actionsNew)
                        group("Closed", diff.actionsClosed)
                        group("Open earlier, not listed later", diff.actionsNotListed)
                    }
                }
                if diff.agendaChangeCount > 0 {
                    card(title: "Agenda", icon: "list.bullet.rectangle", badge: "Changed") {
                        group("Added", diff.agendaAdded)
                        group("Removed", diff.agendaRemoved)
                    }
                }
                if diff.attendanceChangeCount > 0 {
                    card(title: "Attendance", icon: "person.2", badge: "Changed") {
                        group("Joined", diff.attendeesJoined)
                        group("Not present", diff.attendeesLeft)
                    }
                }
                if !diff.actionsCarried.isEmpty {
                    card(title: "Still Open", icon: "hourglass", badge: nil) {
                        group("Carried over", diff.actionsCarried)
                    }
                }
            }
            .padding(Spacing.lg)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("What Changed")
        .navigationBarTitleDisplayMode(.large)
        .tint(Theme.Colors.manentAccent)
        .safeAreaInset(edge: .bottom) {
            if router != nil {
                Button(action: openLatest) {
                    Text("Open Latest Meeting")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(Theme.Colors.manentAccent, in: Capsule())
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            }
        }
    }

    private func openLatest() {
        appState?.activeTab = .home
        router?.navigate(to: .meetingDetail(id: diff.later.id), in: .home)
    }

    private var headerChips: some View {
        HStack(spacing: Spacing.sm) {
            chip(date: diff.earlier.date, title: diff.earlier.title, highlighted: false)
            Image(systemName: "arrow.right").font(.footnote).foregroundStyle(.secondary)
            chip(date: diff.later.date, title: diff.later.title, highlighted: true)
        }
    }

    private func chip(date: Date, title: String, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(SeriesComparisonView.dateText(date)).font(.caption)
                .foregroundStyle(highlighted ? Theme.Colors.manentAccent : .secondary)
            Text(title).font(.subheadline.weight(.semibold))
                .foregroundStyle(highlighted ? Theme.Colors.manentAccent : .primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? Theme.Colors.manentAccent.opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private func card<Content: View>(title: String, icon: String, badge: String?,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.Colors.manentAccent)
                    .frame(width: 32, height: 32)
                    .background(Theme.Colors.manentAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                Text(title).font(.headline)
                Spacer()
                if let badge {
                    Text(badge).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }
            content()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private func group(_ title: String, _ entries: [SeriesDiffEntry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.text).font(.subheadline)
                        if let detail = entry.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(entry.meetingTitle) \u{00B7} \(SeriesComparisonView.dateText(entry.meetingDate))")
                            .font(.caption).foregroundStyle(Theme.Colors.manentAccent)
                    }
                }
            }
        }
    }
}
