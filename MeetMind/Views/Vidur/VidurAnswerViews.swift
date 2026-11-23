import SwiftUI
import OfflineEngineKit

// Figma "G3 · Vidur" and "G4 · Vidur answer": question bubble, answer card with source chips and
// people, related actions, suggestion rows and follow-up chips.

private enum VidurFigma {
    static let accent = Color(red: 0.310, green: 0.275, blue: 0.898)
    static let secondaryText = Color(red: 0.541, green: 0.541, blue: 0.557)
    static let overdue = Color(red: 1.0, green: 0.231, blue: 0.188)
    static let pending = Color(red: 0.780, green: 0.780, blue: 0.800)
    static let avatarColors: [Color] = [
        Color(red: 1.0, green: 0.624, blue: 0.039), Color(red: 0.188, green: 0.820, blue: 0.345),
        Color(red: 0.0, green: 0.478, blue: 1.0), Color(red: 0.686, green: 0.322, blue: 0.871)
    ]
}

/// Small uppercase section label ("SOURCES", "PEOPLE", "RELATED ACTIONS").
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
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(VidurFigma.avatarColors[abs(colorIndex) % VidurFigma.avatarColors.count], in: Circle())
            .accessibilityHidden(true)
    }
}

/// Loading state: "Thinking…" with a light sweep. Static under Reduce Motion.
struct VidurThinkingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = -0.6

    var body: some View {
        Text("Searching your meetings\u{2026}")
            .font(.body)
            .foregroundStyle(.secondary)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(colors: [Color.clear, Color.white.opacity(0.85), Color.clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.5)
                            .offset(x: sweep * proxy.size.width)
                    }
                    .mask { Text("Searching your meetings\u{2026}").font(.body) }
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { sweep = 1.1 }
            }
            .accessibilityLabel("Vidur is searching")
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
    var isQuick: Bool
    var isRefining: Bool
    var currentMeetingID: UUID?

    var meetingCountText: String? {
        let titles = Set(citations.map(\.meetingTitle))
        guard !titles.isEmpty else { return nil }
        return titles.count == 1 ? "From 1 meeting" : "From \(titles.count) meetings"
    }
}

struct VidurAnswerCard: View {
    let model: VidurAnswerCardModel
    let showsSources: Bool
    /// Opens the meeting or plays the turn behind a source.
    let onOpenSource: (VidurCitation) -> Void
    let onAsk: (String) -> Void

    private func chipTitle(_ citation: VidurCitation) -> String {
        var title = citation.meetingTitle
        if title.count > 22 { title = String(title.prefix(21)) + "\u{2026}" }
        if citation.hasTimestamp { title += " \u{00B7} \(citation.timecode)" }
        else if let label = citation.sourceLabel { title += " \u{00B7} \(label)" }
        return title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(VidurFigma.accent, in: Circle())
                    .accessibilityHidden(true)
                Text("Vidur").font(.subheadline.weight(.semibold))
                Spacer()
                if let count = model.meetingCountText {
                    Text(count).font(.footnote).foregroundStyle(VidurFigma.secondaryText)
                }
            }
            if model.text.isEmpty {
                VidurThinkingView()
            } else {
                Text(model.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.isRefining, !model.text.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Checking the transcript in more depth\u{2026}")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if showsSources, !model.citations.isEmpty {
                VidurSectionLabel(title: "Sources")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.citations) { citation in
                        Button { onOpenSource(citation) } label: {
                            Label(chipTitle(citation), systemImage: citation.hasTimestamp ? "waveform" : "doc.text")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(VidurFigma.accent)
                                .lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(VidurFigma.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(citation.hasTimestamp ? "Plays the recording at this moment" : "Opens the meeting")
                    }
                }
            }
            if !model.people.isEmpty {
                VidurSectionLabel(title: "People")
                HStack(spacing: 14) {
                    ForEach(Array(model.people.prefix(3).enumerated()), id: \.offset) { offset, name in
                        HStack(spacing: 6) {
                            VidurAvatar(name: name, colorIndex: offset)
                            Text(name.split(separator: " ").first.map(String.init) ?? name).font(.subheadline)
                        }
                    }
                }
            }
            if let notice = model.notice, !model.isRefining {
                Label(notice, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
            }
            if !model.suggestions.isEmpty {
                VidurSectionLabel(title: "Try asking")
                VidurFollowUpChips(questions: model.suggestions, onAsk: onAsk)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// "Related actions" list under an answer.
struct VidurRelatedActions: View {
    let tasks: [VidurQuickTask]
    let now: Date
    let onOpen: (VidurQuickTask) -> Void

    private func detail(_ task: VidurQuickTask) -> (text: String, overdue: Bool) {
        var parts: [String] = []
        if let owner = task.owner, !owner.isEmpty { parts.append(owner.split(separator: " ").first.map(String.init) ?? owner) }
        var overdue = false
        if let due = task.dueDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            parts.append("due \(formatter.string(from: due))")
            overdue = !task.isCompleted && due < now
        } else if let text = task.dueText, !text.isEmpty {
            parts.append("due \(text)")
        }
        return (parts.joined(separator: " \u{00B7} "), overdue)
    }

    var body: some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                VidurSectionLabel(title: "Related actions").padding(.leading, 16)
                VStack(spacing: 0) {
                    ForEach(Array(tasks.enumerated()), id: \.offset) { offset, task in
                        let info = detail(task)
                        Button { onOpen(task) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(task.isCompleted ? Color.green : (info.overdue ? VidurFigma.overdue : VidurFigma.pending))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title).foregroundStyle(.primary)
                                    if !info.text.isEmpty {
                                        Text(info.text).font(.footnote)
                                            .foregroundStyle(info.overdue ? VidurFigma.overdue : VidurFigma.secondaryText)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if offset < tasks.count - 1 { Divider().padding(.leading, 52) }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
    }
}

/// Wrapping row of tappable questions.
struct VidurFollowUpChips: View {
    let questions: [String]
    let onAsk: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(questions, id: \.self) { question in
                    Button { onAsk(question) } label: {
                        Text(question)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(VidurFigma.accent)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(VidurFigma.accent.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// One question and its answer: the blue question bubble, the answer card and related actions.
struct VidurConversationRow: View {
    let prompt: String
    let model: VidurAnswerCardModel
    let showsSources: Bool
    let now: Date
    let onOpenSource: (VidurCitation) -> Void
    let onOpenTask: (VidurQuickTask) -> Void
    let onAsk: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(VidurFigma.accent, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
            VidurAnswerCard(model: model, showsSources: showsSources, onOpenSource: onOpenSource, onAsk: onAsk)
            VidurRelatedActions(tasks: model.tasks, now: now, onOpen: onOpenTask)
        }
    }
}

/// G3: suggested questions and recent questions, as inset grouped rows.
struct VidurSuggestionList: View {
    struct Recent: Identifiable {
        let id = UUID()
        let question: String
        let when: String
    }

    let suggestions: [String]
    let recent: [Recent]
    let onAsk: (String) -> Void

    private func row(icon: String, tint: Color, title: String, detail: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let detail { Text(detail).font(.footnote).foregroundStyle(VidurFigma.secondaryText) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    VidurSectionLabel(title: "Suggested").padding(.leading, 16)
                    VStack(spacing: 0) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { offset, question in
                            Button { onAsk(question) } label: {
                                row(icon: "sparkle", tint: VidurFigma.accent, title: question, detail: nil)
                            }
                            .buttonStyle(.plain)
                            if offset < suggestions.count - 1 { Divider().padding(.leading, 52) }
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                    .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
        }
    }
}
