import SwiftUI

/// Segmented All / Meetings / Transcripts / Actions control shown above search results.
public struct SearchPresentedScopeBar: View {
    public let selected: SearchPresentedScope
    public let onSelect: (SearchPresentedScope) -> Void

    public init(selected: SearchPresentedScope, onSelect: @escaping (SearchPresentedScope) -> Void) {
        self.selected = selected
        self.onSelect = onSelect
    }

    public var body: some View {
        Picker("Search scope", selection: Binding(get: { selected }, set: { onSelect($0) })) {
            ForEach(SearchPresentedScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
    }
}

/// Small month/day tile used by meeting search rows.
struct SearchDateTile: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.red)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(.primary)
        }
        .frame(width: 40, height: 40)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Grouped search results: Meetings, Transcripts and Actions cards (Figma "Search · Results").
public struct SearchResultSectionsView: View {
    public let viewModel: SearchViewModel
    public let meetings: [Meeting]
    public let onOpen: (UUID) -> Void

    public init(viewModel: SearchViewModel, meetings: [Meeting], onOpen: @escaping (UUID) -> Void) {
        self.viewModel = viewModel
        self.meetings = meetings
        self.onOpen = onOpen
    }

    private var showsHeaders: Bool { viewModel.presentedScope == .all }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                let hits = viewModel.meetingHits
                if !hits.isEmpty {
                    card("Meetings", rowCount: hits.count) {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                            meetingRow(hit)
                            if index < hits.count - 1 { Divider().padding(.leading, 68) }
                        }
                    }
                }
                let transcripts = viewModel.transcriptResults
                if !transcripts.isEmpty {
                    card("Transcripts", rowCount: transcripts.count) {
                        ForEach(Array(transcripts.enumerated()), id: \.element.id) { index, item in
                            transcriptRow(item)
                            if index < transcripts.count - 1 { Divider().padding(.leading, 16) }
                        }
                    }
                }
                let actions = viewModel.actionResults
                if !actions.isEmpty {
                    card("Actions", rowCount: actions.count) {
                        ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                            actionRow(item)
                            if index < actions.count - 1 { Divider().padding(.leading, 16) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func card<Content: View>(_ title: String, rowCount: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeaders {
                Text(title).font(.title3.weight(.semibold)).padding(.horizontal, 16)
            }
            VStack(spacing: 0) { content() }
                .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func rowChrome<Leading: View>(
        title: String, subtitle: String?, meetingId: UUID, @ViewBuilder leading: () -> Leading
    ) -> some View {
        Button { onOpen(meetingId) } label: {
            HStack(spacing: 12) {
                leading()
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body).foregroundStyle(.primary).lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 11).frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func meetingRow(_ hit: MeetingSearchHit) -> some View {
        return rowChrome(title: hit.title, subtitle: hit.detail, meetingId: hit.meetingId) {
            Image(systemName: "waveform")
                .foregroundStyle(Theme.Colors.manentAccent)
                .frame(width: 28)
                .accessibilityHidden(true)
        }
    }

    private func transcriptRow(_ item: SearchResultItem) -> some View {
        let title = item.timecode.map { "\(item.meetingTitle) \u{00B7} \(Self.clock($0))" } ?? item.meetingTitle
        let snippet = viewModel.formatSnippet(text: item.snippet, matchTerm: viewModel.trimmedQuery, maxLength: 44)
        let quote = "\u{201C}\(snippet)\u{201D}"
        let subtitle = item.speakerName.map { "\($0): \(quote)" } ?? quote
        return rowChrome(title: title, subtitle: subtitle, meetingId: item.meetingId) {
            Image(systemName: "doc.text")
                .foregroundStyle(Color.teal)
                .frame(width: 28)
                .accessibilityHidden(true)
        }
    }

    private func actionRow(_ item: SearchResultItem) -> some View {
        rowChrome(title: item.snippet, subtitle: item.detail, meetingId: item.meetingId) {
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(Color.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
        }
    }

    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
