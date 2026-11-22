import SwiftUI
import SwiftData
import UIKit

/// Local inbox of app events (Figma 405:638). Entries are derived from saved meetings and
/// tasks, so nothing is sent from or received over a network.
public struct NotificationsInboxView: View {
    @Environment(NavigationRouter.self) private var router: NavigationRouter?
    @Environment(AppState.self) private var appState: AppState?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @Query private var tasks: [ActionItem]

    @State private var readIDs: Set<String> = []

    public init() {}

    private var items: [LocalInboxItem] {
        let meetingInputs = meetings.map {
            LocalInboxMeetingInput(id: $0.id, title: $0.title, date: $0.createdAt,
                                   analysisState: $0.analysisState, hasMinutes: $0.summary != nil)
        }
        let taskInputs = tasks.map {
            LocalInboxTaskInput(id: $0.id, title: $0.title, meetingID: $0.meeting?.id,
                                meetingTitle: $0.meeting?.title, dueDate: $0.dueDate,
                                isCompleted: $0.isCompleted, completedAt: $0.completedAt)
        }
        return LocalInboxBuilder.items(meetings: meetingInputs, tasks: taskInputs, now: Date())
    }

    public var body: some View {
        let entries = items
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Updates Yet",
                    systemImage: "bell",
                    description: Text("Finished minutes, processing problems and task deadlines from your meetings appear here.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section("Updates from Your Meetings") {
                    ForEach(entries) { item in
                        Button { open(item) } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(readIDs.contains(item.id) ? Color.clear : Theme.Colors.manentAccent)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.kind.title).foregroundStyle(.primary)
                                    Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(dateText(for: item)).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                Button("Notification Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } footer: {
                Text("This list is built from meetings saved on this iPhone. Manent sends no remote notifications.")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark All Read") {
                    let store = LocalInboxReadStore()
                    store.markAllRead(entries)
                    readIDs = store.readIDs
                }
                .disabled(entries.allSatisfy { readIDs.contains($0.id) })
            }
        }
        .onAppear { readIDs = LocalInboxReadStore().readIDs }
    }

    private func open(_ item: LocalInboxItem) {
        let store = LocalInboxReadStore()
        store.markRead(item.id)
        readIDs = store.readIDs
        appState?.activeTab = .home
        router?.navigate(to: .meetingDetail(id: item.meetingID), in: .home)
    }

    private func dateText(for item: LocalInboxItem) -> String {
        let calendar = Calendar.current
        let formatted = item.date.formatted(.dateTime.day().month(.abbreviated))
        switch item.kind {
        case .taskDue, .taskOverdue:
            return calendar.isDateInToday(item.date) ? "Due Today" : "Due \(formatted)"
        default:
            return calendar.isDateInToday(item.date) ? "Today" : formatted
        }
    }
}

/// H8 Allow Notifications row. Shows the real iOS authorization state and opens the right place to change it.
private struct NotificationAccessRow: View {
    @Environment(\.openURL) private var openURL
    @State private var status: UNAuthorizationStatus = .notDetermined

    private var isOn: Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconTile(systemImage: "bell.fill", color: .red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow Notifications").font(.subheadline)
                Text(isOn ? "Minutes ready and task reminders can alert you." : "Off. Manent will not alert you.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Button(isOn ? "Manage" : (status == .notDetermined ? "Allow" : "Open Settings")) { change() }
                .font(.subheadline.weight(.semibold))
        }
        .task { await refresh() }
    }

    private func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func change() {
        if status == .notDetermined {
            Task {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                await refresh()
            }
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
