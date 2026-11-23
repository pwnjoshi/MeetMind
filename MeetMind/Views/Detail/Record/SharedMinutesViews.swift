import SwiftUI

/// Local adaptation of "Open shared minutes". There is no sign-in or verification code.
/// The user picks one of the copies they handed to Mail or the share sheet from this iPhone and opens a read-only preview.
@MainActor
struct OpenSharedMinutesView: View {
    let meetingID: UUID
    @State private var selectedID: UUID?
    @State private var opened: SharedMinutesEntry?

    private var entries: [SharedMinutesEntry] {
        MeetingRecordStore.shared.record(for: meetingID).shares.sorted { $0.date > $1.date }
    }

    private var selected: SharedMinutesEntry? {
        entries.first(where: { $0.id == selectedID }) ?? entries.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Open Shared Minutes").font(.largeTitle.bold())
            Text("Choose a copy you shared or exported from this iPhone. Manent keeps the exact text passed to the selected activity and does not know whether anyone opened it.")
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.top, 6)
            if entries.isEmpty {
                ContentUnavailableView("Nothing shared yet", systemImage: "paperplane",
                                       description: Text("Minutes you send from this meeting appear here."))
                    .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    field("Shared With") {
                        Menu {
                            ForEach(entries) { entry in
                                Button {
                                    selectedID = entry.id
                                } label: {
                                    if entry.id == selected?.id {
                                        Label(Self.menuTitle(entry), systemImage: "checkmark")
                                    } else {
                                        Text(Self.menuTitle(entry))
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(selected?.recipientSummary ?? "").foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    field("Shared On") {
                        Text(selected?.date.formatted(date: .long, time: .shortened) ?? "")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 28)
                Spacer()
                Button {
                    opened = selected
                } label: {
                    Text("Open Minutes").frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(.white)
                        .background(Theme.Colors.manentAccent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $opened) { entry in
            SharedMinutesView(entry: entry)
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 16)
            content()
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(.background, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private static func menuTitle(_ entry: SharedMinutesEntry) -> String {
        "\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(entry.recipientSummary)"
    }
}

/// Read-only preview of exactly the text the user handed to Mail or the share sheet.
struct SharedMinutesView: View {
    let entry: SharedMinutesEntry
    @Environment(\.dismiss) private var dismiss

    private struct Block: Identifiable {
        let id: Int
        let heading: String?
        let lines: [String]
    }

    private var blocks: [Block] {
        var result: [Block] = []
        let paragraphs = entry.bodyText.components(separatedBy: "\n\n")
        for paragraph in paragraphs {
            var lines = paragraph.split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.allSatisfy { $0 == "=" } }
            guard !lines.isEmpty else { continue }
            var heading: String?
            if let first = lines.first, first.hasSuffix(":") {
                heading = String(first.dropLast())
                lines.removeFirst()
            }
            result.append(Block(id: result.count, heading: heading, lines: lines))
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.subject).font(.largeTitle.bold())
                    Text("Shared minutes · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Read-only copy of what you passed to \(entry.channel == .mail ? "Mail" : "the system share activity") from this iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(blocks) { block in
                    VStack(alignment: .leading, spacing: 8) {
                        if let heading = block.heading {
                            Text(heading.capitalized).font(.subheadline).foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(block.lines.enumerated()), id: \.offset) { line in
                                Text(line.element).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(16)
                        .background(.background, in: RoundedRectangle(cornerRadius: 24))
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .toolbarProminentTextButtonStyle()
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}
