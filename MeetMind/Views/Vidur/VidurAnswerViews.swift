import SwiftUI
import UIKit
import OfflineEngineKit

// Figma "G3 · Vidur" and "G4 · Vidur answer", as a calm chat: the user's words in an accent bubble on the right,
// Vidur's answer on the left as plain text (inside a card only when it has sources), native rows for lists and
// actions, source chips that open the meeting, and follow-up chips.

enum VidurFigma {
    static let accent = Color(red: 0.310, green: 0.275, blue: 0.898)
    static let secondaryText = Color(red: 0.541, green: 0.541, blue: 0.557)
    static let overdue = Color(red: 1.0, green: 0.231, blue: 0.188)
    static let pending = Color(red: 0.780, green: 0.780, blue: 0.800)
    static let avatarColors: [Color] = [
        Color(red: 1.0, green: 0.624, blue: 0.039), Color(red: 0.188, green: 0.820, blue: 0.345),
        Color(red: 0.0, green: 0.478, blue: 1.0), Color(red: 0.686, green: 0.322, blue: 0.871)
    ]
    /// Rows and cards sit on the grouped background in both light and dark mode.
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}

/// Short names for the scope pill inside the composer.
extension VidurSearchScope {
    var pillTitle: String {
        switch self {
        case .thisMeeting: return "This meeting"
        case .thisMeetingAndSeries: return "Meeting + series"
        case .allMeetings: return "All meetings"
        }
    }
}

/// Small uppercase section label ("SOURCES", "SUGGESTED", "RECENT").
struct VidurSectionLabel: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.footnote)
            .foregroundStyle(VidurFigma.secondaryText)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Coloured circle with initials.
struct VidurAvatar: View {
    let name: String
    let colorIndex: Int

    private var initials: String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }
        return letters.joined()
    }

    var body: some View {
        Text(initials)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(VidurFigma.avatarColors[abs(colorIndex) % VidurFigma.avatarColors.count], in: Circle())
            .accessibilityHidden(true)
    }
}

/// Lays out children left to right and wraps to the next line, so chips never scroll sideways or get cut off.
struct VidurFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: usedWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// "Vidur is reading your meetings…" with a softly pulsing sparkle. The sparkle holds still under Reduce Motion.
struct VidurTypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var label = "Vidur is reading your meetings\u{2026}"
    var font: Font = .subheadline

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(font)
                .foregroundStyle(VidurFigma.accent)
                .symbolEffect(.pulse, isActive: !reduceMotion)
                .accessibilityHidden(true)
            Text(label)
                .font(font)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Everything one answer needs to draw itself.
struct VidurAnswerCardModel {
    var text: String
    var citations: [VidurCitation]
    var people: [String]
    var tasks: [VidurQuickTask]
    var suggestions: [String]
    var notice: String?
    var isRefining: Bool
    var currentMeetingID: UUID?
    /// True while the model is writing the reply, so the words on screen are still growing.
    var isWriting = false
    var completedTaskKeys: Set<String> = []
}

/// Vidur's side of one exchange.
struct VidurAssistantMessage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let prompt: String
    let model: VidurAnswerCardModel
    let showsSources: Bool
    let now: Date
    let onOpenSource: (VidurCitation) -> Void
    let onOpenTask: (VidurQuickTask) -> Void
    let onToggleTask: (VidurQuickTask) -> Void
    let onAsk: (String) -> Void

    private var hasSources: Bool { showsSources && !model.citations.isEmpty }

    private func chipTitle(_ citation: VidurCitation) -> String {
        var title = citation.meetingTitle
        if title.count > 22 { title = String(title.prefix(21)) + "\u{2026}" }
        if citation.hasTimestamp { title += " \u{00B7} \(citation.timecode)" }
        else if let label = citation.sourceLabel { title += " \u{00B7} \(label)" }
        return title
    }

    private var rowSymbol: String {
        let label = model.citations.first?.sourceLabel
        if label == "Decision" { return "checkmark.seal" }
        if label == "Open issue" { return "questionmark.circle" }
        return "circle.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.text.isEmpty {
                VidurTypingIndicator()
            } else {
                answerBody
            }
            if !model.suggestions.isEmpty {
                VidurFollowUpChips(questions: model.suggestions, onAsk: onAsk)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.text.count)
        .contextMenu {
            if !model.text.isEmpty {
                Button {
                    UIPasteboard.general.string = model.text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button {
                    onAsk(prompt)
                } label: {
                    Label("Ask again", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    @ViewBuilder
    private var answerBody: some View {
        let layout = VidurAnswerLayout.parse(model.text)
        let showsRows = !layout.bullets.isEmpty && model.tasks.isEmpty
        VStack(alignment: .leading, spacing: 12) {
            if !layout.intro.isEmpty {
                Text(layout.intro)
                    .font(.body)
                    .lineSpacing(3)
                    .contentTransition(.identity)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Vidur says: " + layout.intro)
            }
            if showsRows {
                resultRows(layout.bullets)
            } else if !model.tasks.isEmpty {
                taskRows(extra: max(0, layout.bullets.count - model.tasks.count))
            }
            if showsRows, !layout.outro.isEmpty {
                Text(layout.outro).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.isRefining {
                VidurTypingIndicator(
                    label: model.isWriting ? "Writing from your meetings\u{2026}" : "Checking the transcript in more depth\u{2026}",
                    font: .footnote)
            }
            if hasSources { sources }
            if hasSources, !model.people.isEmpty { people }
            if let notice = model.notice, !model.isRefining {
                Label(notice, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(hasSources ? 16 : 0)
        .background {
            if hasSources {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(VidurFigma.surface)
            }
        }
    }

    // MARK: Parts

    private var sources: some View {
        VStack(alignment: .leading, spacing: 6) {
            VidurSectionLabel(title: "Sources")
            VidurFlowLayout(spacing: 8) {
                ForEach(model.citations) { citation in
                    Button { onOpenSource(citation) } label: {
                        Label(chipTitle(citation), systemImage: citation.hasTimestamp ? "waveform" : "doc.text")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(VidurFigma.accent)
                            .lineLimit(1)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(VidurFigma.accent.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Source: \(citation.meetingTitle)" + (citation.hasTimestamp ? " at \(citation.timecode)" : ""))
                    .accessibilityHint(citation.hasTimestamp ? "Plays the recording at this moment" : "Opens the meeting")
                }
            }
        }
    }

    private var people: some View {
        HStack(spacing: 14) {
            ForEach(Array(model.people.prefix(3).enumerated()), id: \.offset) { offset, name in
                HStack(spacing: 6) {
                    VidurAvatar(name: name, colorIndex: offset)
                    Text(name.split(separator: " ").first.map(String.init) ?? name).font(.subheadline)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A list of decisions or open issues, one native row each.
    private func resultRows(_ bullets: [String]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(bullets.enumerated()), id: \.offset) { offset, line in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: rowSymbol)
                        .font(rowSymbol == "circle.fill" ? Font.system(size: 6) : Font.body)
                        .foregroundStyle(VidurFigma.accent)
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                    Text(line)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .accessibilityElement(children: .combine)
                if offset < bullets.count - 1 { Divider().padding(.leading, 48) }
            }
        }
        .background(VidurFigma.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func detail(_ task: VidurQuickTask) -> (text: String, overdue: Bool) {
        var parts: [String] = []
        if let owner = task.owner, !owner.isEmpty { parts.append(owner.split(separator: " ").first.map(String.init) ?? owner) }
        var overdue = false
        if let due = task.dueDate {
            parts.append("due " + due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            overdue = !task.isCompleted && due < now
        } else if let text = task.dueText, !text.isEmpty {
            parts.append("due \(text)")
        }
        return (parts.joined(separator: " \u{00B7} "), overdue)
    }

    /// Actions with owner and due date. The circle marks one done after a confirmation.
    private func taskRows(extra: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(model.tasks.enumerated()), id: \.offset) { offset, task in
                let info = detail(task)
                let done = task.isCompleted || model.completedTaskKeys.contains(VidurTaskKey.key(for: task))
                HStack(spacing: 4) {
                    Button { onToggleTask(task) } label: {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(done ? Color.green : (info.overdue ? VidurFigma.overdue : VidurFigma.pending))
                            .frame(width: 40, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(done)
                    .accessibilityLabel(done ? "Done: \(task.title)" : "Mark \(task.title) as done")
                    .accessibilityHint(done ? "" : "Asks you to confirm first")
                    Button { onOpenTask(task) } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .strikethrough(done)
                                    .multilineTextAlignment(.leading)
                                if !info.text.isEmpty {
                                    Text(info.text)
                                        .font(.footnote)
                                        .foregroundStyle(info.overdue && !done ? VidurFigma.overdue : VidurFigma.secondaryText)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the meeting")
                }
                .padding(.leading, 6).padding(.trailing, 14)
                if offset < model.tasks.count - 1 { Divider().padding(.leading, 50) }
            }
            if extra > 0 {
                Divider().padding(.leading, 50)
                Text("and \(extra) more in your meetings")
                    .font(.footnote)
                    .foregroundStyle(VidurFigma.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .background(VidurFigma.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Tappable follow-up questions under an answer.
struct VidurFollowUpChips: View {
    let questions: [String]
    let onAsk: (String) -> Void

    var body: some View {
        VidurFlowLayout(spacing: 8) {
            ForEach(questions, id: \.self) { question in
                Button { onAsk(question) } label: {
                    Text(question)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(VidurFigma.accent)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(VidurFigma.accent.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Asks Vidur this question")
            }
        }
    }
}

/// One question and its answer.
struct VidurConversationRow: View {
    let prompt: String
    let model: VidurAnswerCardModel
    let showsSources: Bool
    let now: Date
    let onOpenSource: (VidurCitation) -> Void
    let onOpenTask: (VidurQuickTask) -> Void
    let onToggleTask: (VidurQuickTask) -> Void
    let onAsk: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VidurPromptBubble(text: prompt)
            VidurAssistantMessage(prompt: prompt, model: model, showsSources: showsSources, now: now,
                                  onOpenSource: onOpenSource, onOpenTask: onOpenTask,
                                  onToggleTask: onToggleTask, onAsk: onAsk)
        }
    }
}

/// G3: a greeting by name, one line about what needs attention, smart suggestions and recent questions.
struct VidurEmptyState: View {
    struct Recent: Identifiable {
        let id = UUID()
        let question: String
        let when: String
    }

    let title: String
    let insight: String?
    let detail: String
    let suggestions: [VidurSmartSuggestion]
    let recent: [Recent]
    let onAsk: (String) -> Void

    private func row(icon: String, tint: Color, title: String, detail: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary).multilineTextAlignment(.leading)
                if let detail { Text(detail).font(.footnote).foregroundStyle(VidurFigma.secondaryText) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    VidurSectionLabel(title: "Suggested").padding(.leading, 16)
                    VStack(spacing: 0) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { offset, suggestion in
                            Button { onAsk(suggestion.text) } label: {
                                row(icon: suggestion.symbol, tint: VidurFigma.accent, title: suggestion.text, detail: nil)
                            }
                            .buttonStyle(.plain)
                            if offset < suggestions.count - 1 { Divider().padding(.leading, 52) }
                        }
                    }
                    .background(VidurFigma.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    VidurSectionLabel(title: "Recent").padding(.leading, 16)
                    VStack(spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.offset) { offset, item in
                            Button { onAsk(item.question) } label: {
                                row(icon: "clock", tint: VidurFigma.secondaryText, title: item.question, detail: item.when)
                            }
                            .buttonStyle(.plain)
                            if offset < recent.count - 1 { Divider().padding(.leading, 52) }
                        }
                    }
                    .background(VidurFigma.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            Text("Vidur runs on this iPhone and uses a small on-device model. It relies on your saved minutes and transcripts, and tells you when it can\u{2019}t find something. Your meetings never leave your phone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(VidurFigma.accent, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let insight {
                    Text(insight)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(VidurFigma.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [VidurFigma.accent.opacity(0.14), Color.cyan.opacity(0.12)],
                startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The message field with a send button and the scope pill, inside one rounded container.
struct VidurComposer: View {
    @Binding var text: String
    @Binding var scope: VidurSearchScope
    let placeholder: String
    let canSend: Bool
    let showsScope: Bool
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                Image(systemName: "sparkle")
                    .foregroundStyle(VidurFigma.accent)
                    .padding(.bottom, 6)
                    .accessibilityHidden(true)
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.vertical, 6)
                    .accessibilityLabel("Message Vidur")
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(canSend ? VidurFigma.accent : VidurFigma.pending)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            if showsScope {
                Menu {
                    Picker("Search in", selection: $scope) {
                        ForEach(VidurSearchScope.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.magnifyingglass").font(.caption)
                        Text(scope.pillTitle)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(VidurFigma.accent)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(VidurFigma.accent.opacity(0.10), in: Capsule())
                }
                .accessibilityLabel("Searching in \(scope.pillTitle)")
                .accessibilityHint("Choose which meetings Vidur reads")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.primary.opacity(0.06)))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
