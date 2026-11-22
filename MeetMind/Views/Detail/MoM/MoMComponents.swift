import SwiftUI

/// Small building blocks of the Minutes of Meeting document (Figma B6).
struct MoMSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

struct MoMCaption: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

struct MoMCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct MoMStatusPill: View {
    let status: MoMStatusKind

    private var tint: Color { status == .draft ? Color.orange : Color.green }

    var body: some View {
        Text(status.text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
            .accessibilityLabel("Status: \(status.text)")
    }
}

struct MoMAvatar: View {
    let initials: String
    let colorHex: String
    var size: CGFloat = 32

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: colorHex), in: Circle())
            .accessibilityHidden(true)
    }
}

struct MoMPersonRowView: View {
    let row: MoMDocumentModel.PersonRow
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                MoMAvatar(initials: row.initials, colorHex: row.colorHex)
                Text(row.name).font(.body).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(row.trailing)
                    .font(.subheadline)
                    .foregroundStyle(row.isLeaveGranted ? Color.green : Color.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(row.name)")
    }
}

/// RESOLVED THAT (green), DEFERRED (orange) or OPEN with the source chip that plays the audio.
struct MoMOutcomeBox: View {
    let topic: MoMTopic
    let canPlay: Bool
    let onPlay: (Double) -> Void

    private var tint: Color {
        switch topic.outcomeKind {
        case .resolved: return .green
        case .deferred: return .orange
        case .open: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(tint).frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(topic.outcomeKind.label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                Text(topic.outcomeText).font(.subheadline.weight(.medium))
                if let chip = topic.sourceChipText, let time = topic.timestamp {
                    Button { onPlay(time) } label: {
                        Label(chip, systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Colors.manentAccent)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.Colors.manentAccent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canPlay)
                    .opacity(canPlay ? 1 : 0.5)
                    .accessibilityLabel("Play \(chip)")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct MoMTopicCard: View {
    let number: String
    let topic: MoMTopic
    let canPlay: Bool
    let onPlay: (Double) -> Void

    var body: some View {
        MoMCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(number)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.Colors.manentAccent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.Colors.manentAccent.opacity(0.12), in: Capsule())
                    Text(topic.title).font(.headline)
                }
                .accessibilityElement(children: .combine)
                if !topic.discussion.isEmpty {
                    Text("DISCUSSION").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(topic.discussion.enumerated()), id: \.offset) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\u{2022}").foregroundStyle(.secondary)
                            Text(entry.element).font(.subheadline)
                        }
                    }
                }
                if topic.hasOutcome {
                    MoMOutcomeBox(topic: topic, canPlay: canPlay, onPlay: onPlay)
                }
            }
            .padding(16)
        }
    }
}

struct MoMActionTable: View {
    let rows: [MoMDocumentModel.ActionRow]
    let onToggle: (MoMDocumentModel.ActionRow) -> Void

    var body: some View {
        MoMCard {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("#").frame(width: 20, alignment: .leading)
                    Text("ACTION").frame(maxWidth: .infinity, alignment: .leading)
                    Text("BY").frame(width: 52, alignment: .leading)
                    Text("TARGET").frame(width: 50, alignment: .leading)
                    Text("STATUS").frame(width: 56, alignment: .trailing)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 10)
                ForEach(rows) { row in
                    Divider()
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(row.number)").foregroundStyle(.secondary).frame(width: 20, alignment: .leading)
                        Text(row.title).frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.by).frame(width: 52, alignment: .leading)
                        Text(row.target).frame(width: 50, alignment: .leading)
                        Button { onToggle(row) } label: {
                            Text(row.isDone ? "Done" : "Open")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(row.isDone ? Color.green : Color.orange)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background((row.isDone ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                                .frame(minWidth: 56, minHeight: 44, alignment: .trailing)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(row.isDone ? "Mark \(row.title) open" : "Mark \(row.title) done")
                    }
                    .font(.footnote)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
            }
        }
    }
}
