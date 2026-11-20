import SwiftUI
import SwiftData

/// Native preparation record for a scheduled meeting before capture begins.
public struct ScheduledMeetingDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let meeting: Meeting
    @Query private var meetings: [Meeting]
    @State private var editing = false
    @State private var peopleSheet = false
    @State private var errorMessage: String?

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text(meeting.title).font(.largeTitle.bold())
                detailsCard
                peopleSection
                earlierMeetings
                minutesSection
                Color.clear.frame(height: 90)
            }
            .padding(.horizontal, 20).padding(.top, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") { save() }.labelStyle(.iconOnly)
                    .tint(Theme.Colors.manentAccent)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Start recording") { startRecording() }
                .frame(maxWidth: .infinity).buttonStyle(.borderedProminent)
                .tint(Theme.Colors.manentAccent).buttonBorderShape(.capsule).controlSize(.large)
                .padding(.horizontal, 20).padding(.vertical, 10).background(.regularMaterial)
        }
        .sheet(isPresented: $editing) { editor }
        .sheet(isPresented: $peopleSheet) { peopleEditor }
        .alert("Could Not Save Meeting", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            detailButton("Date & Time", value: (meeting.scheduledStartTime ?? meeting.createdAt).formatted(date: .abbreviated, time: .shortened)) { editing = true }
            Divider().padding(.leading, 16)
            detailButton("Repeat", value: meeting.seriesID == nil ? "Never" : "Repeats weekly") { editing = true }
            Divider().padding(.leading, 16)
            detailButton("Agenda", value: meeting.agendaText?.isEmpty == false ? meeting.agendaText! : "Add agenda") { editing = true }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func detailButton(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title).foregroundStyle(.primary); Spacer(); Text(value).foregroundStyle(.secondary).lineLimit(1); Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary) }
                .padding(.horizontal, 16).frame(minHeight: 51)
        }.buttonStyle(.plain)
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("People").font(.headline).foregroundStyle(.secondary); Spacer(); Button("Edit") { peopleSheet = true } }
            VStack(spacing: 0) {
                ForEach(meeting.participants, id: \.id) { person in
                    HStack(spacing: 12) {
                        Text(person.initials).font(.caption.bold()).foregroundStyle(.white).frame(width: 32, height: 32).background(Color(hex: person.avatarColorHex), in: Circle())
                        VStack(alignment: .leading, spacing: 2) { Text(person.name); Text(person.email ?? "No email").font(.subheadline).foregroundStyle(.secondary) }
                        Spacer(); if person.name == "Dr. Sachin Ghai" { Text("Organizer").foregroundStyle(.secondary) }
                    }.padding(.horizontal, 16).padding(.vertical, 9)
                }
                Button("Add People") { peopleSheet = true }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }.background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var earlierMeetings: some View {
        let earlier = meetings.filter { $0.seriesID == meeting.seriesID && $0.id != meeting.id && $0.status != .scheduled }
        return Group {
            if !earlier.isEmpty { VStack(alignment: .leading, spacing: 10) { Text("Earlier meetings").font(.headline).foregroundStyle(.secondary); ForEach(earlier) { prior in HStack { VStack(alignment: .leading) { Text(prior.title); Text(prior.figmaBadgeText).font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Text(prior.createdAt.formatted(.dateTime.day().month(.abbreviated))).foregroundStyle(.secondary); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }.padding(16) }.background(.background, in: RoundedRectangle(cornerRadius: 20)) } }
        }
    }

    private var minutesSection: some View {
        VStack(alignment: .leading, spacing: 10) { Text("Minutes").font(.headline).foregroundStyle(.secondary); VStack(spacing: 0) { detailButton("Coordinator", value: "Dr. Sachin Ghai") {}; Divider().padding(.leading, 16); detailButton("Minutes Format", value: meeting.templateName ?? "Project review") {} }.background(.background, in: RoundedRectangle(cornerRadius: 22)) }
    }

    private var editor: some View {
        NavigationStack { Form { Section { TextField("Title", text: Binding(get: { meeting.title }, set: { meeting.title = $0 })); DatePicker("Date & Time", selection: Binding(get: { meeting.scheduledStartTime ?? meeting.createdAt }, set: { meeting.scheduledStartTime = $0 })); TextField("Agenda", text: Binding(get: { meeting.agendaText ?? "" }, set: { meeting.agendaText = $0 }), axis: .vertical) } }.navigationTitle("Meeting details").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = false; save() } } } }
    }

    private var peopleEditor: some View {
        NavigationStack { List(meeting.participants, id: \.id) { Text($0.name) }.navigationTitle("People").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { peopleSheet = false; save() } } } }
    }

    private func save() { do { try context.save() } catch { errorMessage = error.localizedDescription } }
    private func startRecording() { meeting.status = .recording; save() }
}
