import SwiftUI

/// Segmented tab picker for the meeting cockpit (Summary, Transcript, Action Items, Notes & Media)
public struct MeetingDetailTabBarView: View {
    public let selectedTab: MeetingDetailTab
    public let onSelectTab: (MeetingDetailTab) -> Void
    
    public init(selectedTab: MeetingDetailTab, onSelectTab: @escaping (MeetingDetailTab) -> Void) {
        self.selectedTab = selectedTab
        self.onSelectTab = onSelectTab
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(MeetingDetailTab.allCases, id: \.self) { tab in
                    let isSelected = tab == selectedTab
                    Button {
                        onSelectTab(tab)
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: icon(for: tab))
                                .font(.system(size: 12))
                            Text(tab.title)
                                .font(Typography.subheadline)
                                .fontWeight(isSelected ? .bold : .medium)
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .foregroundStyle(isSelected ? .white : Theme.Colors.textSecondary)
                        .background(isSelected ? Theme.Colors.primarySlate : Theme.Colors.cardBackground)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(isSelected ? Theme.Colors.primarySlate : Theme.Colors.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.xs)
        }
    }
    
    private func icon(for tab: MeetingDetailTab) -> String {
        switch tab {
        case .summary: return "doc.text.fill"
        case .transcript: return "waveform.badge.magnifyingglass"
        case .actionItems: return "checklist"
        case .notesMedia: return "photo.on.rectangle.angled"
        }
    }
}
