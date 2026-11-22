import SwiftUI

/// Person page opened from the Attendance rows (Figma B6g): open actions, decisions, talk time,
/// voice samples and contact details, all from data stored on this iPhone.
@MainActor
struct MoMPersonPage: View {
    let person: Speaker
    let meeting: Meeting
    let onPlay: (Double) -> Void
    @Environment(\.openURL) private var openURL
    @State private var player = VoiceSamplePlayer()

    private var segments: [TranscriptSegment] {
        meeting.orderedTranscriptSegments.filter { $0.speaker?.id == person.id }
    }

    private var voiceRow: MeetingVoiceRow {
        MeetingVoiceRow(id: person.id.uuidString, label: person.name,
                        sampleText: segments.first?.text ?? "", startTime: segments.first?.startTime ?? 0,
                        segmentIDs: segments.map(\.id), assignedPersonID: person.id)
    }

    private var openActions: [ActionItem] {
        person.assignedActionItems.filter { !$0.isCompleted }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var decisions: [MeetingMinutesContent.Decision] {
        let content = MeetingMinutesContent.make(from: meeting, record: MeetingRecordStore.shared.record(for: meeting.id))
        return content.decisions.filter { $0.decidedBy == person.name }
    }

    private var meetingsTogether: [Meeting] {
        person.meetings.sorted { ($0.scheduledStartTime ?? $0.createdAt) > ($1.scheduledStartTime ?? $1.createdAt) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                contactButtons
                waitingOn
                if !decisions.isEmpty { decisionsCard }
                lastSaid
                voiceSamples
                togetherCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            MoMAvatar(initials: person.initials, colorHex: person.avatarColorHex, size: 84)
            Text(person.name).font(.title2.bold())
            let role = (person.role ?? "").isEmpty ? "Member" : (person.role ?? "Member")
            let count = meetingsTogether.count
            Text("\(role) \u{00B7} \(count) \(count == 1 ? "meeting" : "meetings") together")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var contactButtons: some View {
        if let email = person.email, !email.isEmpty {
            Button {
                if let url = URL(string: "mailto:\(email)") { openURL(url) }
            } label: {
                Label("Mail \(MeetingRecordFormatting.firstName(person.name))", systemImage: "envelope")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        } else {
            Text("No email saved. Add one from People to send minutes to \(MeetingRecordFormatting.firstName(person.name)).")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var waitingOn: some View {
        VStack(alignment: .leading, spacing: 8) {
            MoMSectionTitle(text: "Waiting On")
            MoMCard {
                if openActions.isEmpty {
                    Text("Nothing open.").font(.subheadline).foregroundStyle(.secondary).padding(16)
                } else {
                    ForEach(openActions, id: \.id) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "circle").font(.title3)
                                .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.subheadline)
                                Text([item.meeting?.title, item.formattedDueDate.map { "due \($0)" }]
                                    .compactMap { $0 }.joined(separator: " \u{00B7} "))
                                    .font(.footnote)
                                    .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16).frame(minHeight: 56)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var decisionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            MoMSectionTitle(text: "Decisions")
            MoMCard {
                ForEach(decisions) { decision in
                    Text(decision.text).font(.subheadline).padding(16)
                }
            }
        }
    }

    private var lastSaid: some View {
        VStack(alignment: .leading, spacing: 8) {
            MoMSectionTitle(text: "Last Said")
            MoMCard {
                if let last = segments.last {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\u{201C}\(last.text.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}").font(.body)
                        let stats = MeetingVoiceSamples.stats(for: voiceRow, in: meeting)
                        Text("Talk time \(stats.summaryText)").font(.footnote).foregroundStyle(.secondary)
                        if meeting.resolvedAudioFileURL != nil {
                            Button { onPlay(last.startTime) } label: {
                                Label("\(meeting.title) \u{00B7} \(last.formattedStartTime)", systemImage: "play.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.Colors.manentAccent)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Theme.Colors.manentAccent.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                } else {
                    Text("No transcript lines are assigned to \(MeetingRecordFormatting.firstName(person.name)) in this meeting.")
                        .font(.subheadline).foregroundStyle(.secondary).padding(16)
                }
            }
        }
    }

    @ViewBuilder
    private var voiceSamples: some View {
        let samples = MeetingVoiceSamples.samples(for: voiceRow, in: meeting)
        if !samples.isEmpty, let url = meeting.resolvedAudioFileURL {
            VStack(alignment: .leading, spacing: 8) {
                MoMSectionTitle(text: "Voice Samples")
                MoMCard {
                    ForEach(samples) { sample in
                        Button { player.toggle(sample, audioURL: url) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: player.isPlaying(sample) ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.title2).foregroundStyle(Theme.Colors.manentAccent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sample.text).font(.subheadline).lineLimit(2).foregroundStyle(.primary)
                                    Text(sample.timestampText).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16).frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var togetherCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MoMSectionTitle(text: "Meetings Together")
                Text("\(meetingsTogether.count)").foregroundStyle(Theme.Colors.manentAccent)
            }
            MoMCard {
                ForEach(meetingsTogether.prefix(8), id: \.id) { item in
                    HStack(spacing: 12) {
                        let date = item.scheduledStartTime ?? item.createdAt
                        VStack(spacing: 0) {
                            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                                .font(.system(size: 9, weight: .bold)).foregroundStyle(.red)
                            Text(date.formatted(.dateTime.day())).font(.headline)
                        }
                        .frame(width: 40, height: 40)
                        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline)
                            Text(item.formattedDuration).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).frame(minHeight: 56)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
