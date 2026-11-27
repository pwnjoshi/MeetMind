import SwiftUI
import UIKit

/// Time-based group of actions on the v5 Actions screen.
struct ActionTimeBucket: Identifiable {
    let id: String
    let title: String
    let isOverdue: Bool
    let items: [ActionItem]

    static func make(from items: [ActionItem], now: Date = Date(), calendar: Calendar = .current) -> [ActionTimeBucket] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday

        var overdue: [ActionItem] = []
        var today: [ActionItem] = []
        var thisWeek: [ActionItem] = []
        var later: [ActionItem] = []
        var undated: [ActionItem] = []
        var completed: [ActionItem] = []

        for item in items {
            if item.isCompleted {
                completed.append(item)
            } else if let due = item.dueDate {
                if due < startOfToday {
                    overdue.append(item)
                } else if due < startOfTomorrow {
                    today.append(item)
                } else if due < endOfWeek {
                    thisWeek.append(item)
                } else {
                    later.append(item)
                }
            } else {
                undated.append(item)
            }
        }

        var result: [ActionTimeBucket] = []
        func add(_ id: String, _ title: String, _ list: [ActionItem], overdue isOverdue: Bool = false) {
            if !list.isEmpty {
                result.append(ActionTimeBucket(id: id, title: title, isOverdue: isOverdue, items: list))
            }
        }
        add("overdue", "Overdue", overdue, overdue: true)
        add("today", "Today", today)
        add("week", "This Week", thisWeek)
        add("later", "Later", later)
        add("undated", "No Due Date", undated)
        add("completed", "Completed", completed)
        return result
    }
}

/// Numbers for the "3 of 8 done this week" card.
struct ActionWeekSummary {
    let done: Int
    let total: Int
    let overdue: Int
    let dueToday: Int

    var progress: Double {
        total == 0 ? 0 : Double(done) / Double(total)
    }

    static func make(from items: [ActionItem], now: Date = Date(), calendar: Calendar = .current) -> ActionWeekSummary {
        let startOfToday = calendar.startOfDay(for: now)
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        var done = 0
        var total = 0
        var overdue = 0
        var dueToday = 0
        for item in items {
            guard let due = item.dueDate else { continue }
            if !item.isCompleted && due < startOfToday { overdue += 1 }
            if !item.isCompleted && due >= startOfToday && due < startOfTomorrow { dueToday += 1 }
            if due < endOfWeek && (due >= startOfToday || item.isCompleted == false) {
                total += 1
                if item.isCompleted { done += 1 }
            }
        }
        return ActionWeekSummary(done: done, total: total, overdue: overdue, dueToday: dueToday)
    }
}

struct ActionsWeekSummaryCard: View {
    let summary: ActionWeekSummary

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Theme.Colors.manentAccent.opacity(0.15), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: summary.progress)
                    .stroke(Theme.Colors.manentAccent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(summary.done)/\(summary.total)")
                    .font(.footnote.weight(.semibold))
            }
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(summary.done) of \(summary.total) done this week")
                    .font(.subheadline.weight(.semibold))
                detailText
                    .font(.footnote)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var detailText: Text {
        let overdue = Text("\(summary.overdue) overdue").foregroundColor(summary.overdue > 0 ? Color.red : Color.secondary)
        let today = Text(" \u{00B7} \(summary.dueToday) due today").foregroundColor(Color.secondary)
        return overdue + today
    }
}

/// Profile avatar in the top bar. Opens Settings on the given tab's stack.
struct ProfileToolbarButton: View {
    let tab: TabIdentifier
    @Environment(NavigationRouter.self) private var router
    @Environment(SettingsViewModel.self) private var settings: SettingsViewModel?

    var body: some View {
        Button {
            router.navigate(to: .settings, in: tab)
        } label: {
            avatar
        }
        .accessibilityLabel("Profile and settings")
    }

    @ViewBuilder
    private var avatar: some View {
        if let data = settings?.userProfile?.avatarImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(Circle())
        } else {
            // iOS 26 draws the glass circle around the toolbar item, so no circle glyph inside it.
            Image(systemName: ToolbarGlass.isSystemProvided ? "person.fill" : "person.crop.circle.fill")
        }
    }
}