import SwiftUI

/// Keyboard helper shared by the schedule sheet and the scheduled meeting page.
enum PrepKeyboard {
    /// Closes the keyboard whichever field has it. Call before presenting a picker or sheet.
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Rounded tinted label used for the repeat, follows-up and important pills.
struct PrepPill: View {
    let text: String
    var systemImage: String?
    var tint: Color = Theme.Colors.manentAccent
    var trailingSymbol: String? = "chevron.down"
    var isFilled: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
            }
            Text(text)
                .multilineTextAlignment(.leading)
            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.caption.weight(.bold))
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(tint.opacity(isFilled ? 0.22 : 0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Value of the Date & Time row: one line when it fits, otherwise day on top and time below. Never truncated.
struct PrepDateTimeValue: View {
    let start: Date
    let end: Date

    var body: some View {
        let day = PrepareMeetingFormat.dayText(start)
        let range = PrepareMeetingFormat.timeRange(start: start, end: end)
        ViewThatFits(in: .horizontal) {
            Text(day + " \u{00B7} " + range)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .trailing, spacing: 2) {
                Text(day)
                Text(range)
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .trailing, spacing: 2) {
                Text(day)
                Text(range)
            }
            .multilineTextAlignment(.trailing)
        }
        .foregroundStyle(PrepStyle.secondaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Date and time")
        .accessibilityValue(day + ", " + range)
    }
}

/// Date and time editing without a popover: graphical calendar, then compact start and end times.
/// Changing the start keeps the meeting length.
struct MeetingDateTimeEditor: View {
    @Binding var start: Date
    @Binding var end: Date
    var error: String?
    let onStartChange: (Date) -> Void

    private var startBinding: Binding<Date> {
        Binding(get: { start }, set: { onStartChange($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            DatePicker("Date", selection: startBinding, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(Theme.Colors.manentAccent)
                .padding(.horizontal, 8)
            Divider().padding(.leading, 16)
            timeRow(title: "Starts") {
                DatePicker("Starts", selection: startBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            Divider().padding(.leading, 16)
            timeRow(title: "Ends") {
                DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.coralRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else if let length = Self.lengthText(start: start, end: end) {
                Text(length)
                    .font(.footnote)
                    .foregroundStyle(PrepStyle.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .tint(Theme.Colors.manentAccent)
    }

    private func timeRow<Control: View>(title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }

    /// "Length 45 min" or "Length 1 h 15 min"; nil when the end is not after the start.
    static func lengthText(start: Date, end: Date) -> String? {
        let minutes = Int((end.timeIntervalSince(start) / 60).rounded())
        guard minutes > 0 else { return nil }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "Length \(rest) min" }
        if rest == 0 { return "Length \(hours) h" }
        return "Length \(hours) h \(rest) min"
    }
}

/// Date and time editing on the scheduled meeting page, shown in a sheet that fits its content.
struct MeetingDateTimeSheet: View {
    @Binding var start: Date
    @Binding var end: Date
    var error: String?
    let onStartChange: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                PrepCard {
                    MeetingDateTimeEditor(start: $start, end: $end, error: error, onStartChange: onStartChange)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .background(PrepStyle.background.ignoresSafeArea())
            .navigationTitle("Date & Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    PrepConfirmButton { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Picker for the "Follows up on" link: recent recorded meetings (same or similar title first), plus None.
struct FollowUpPickerSheet: View {
    let candidates: [Meeting]
    let currentID: UUID?
    let onSelect: (Meeting?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Meeting] {
        let key = MeetingFollowUpLink.normalizedTitle(search)
        guard !key.isEmpty else { return candidates }
        return candidates.filter { MeetingFollowUpLink.normalizedTitle($0.title).contains(key) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        optionRow(title: "None", subtitle: nil, selected: currentID == nil)
                    }
                }
                Section {
                    if filtered.isEmpty {
                        Text(candidates.isEmpty ? "No recorded meetings yet." : "No meetings match your search.")
                            .foregroundStyle(PrepStyle.secondaryText)
                    }
                    ForEach(filtered, id: \.id) { meeting in
                        Button {
                            onSelect(meeting)
                            dismiss()
                        } label: {
                            optionRow(
                                title: meeting.title,
                                subtitle: MeetingFollowUpLink.date(of: meeting).formatted(date: .abbreviated, time: .shortened),
                                selected: meeting.id == currentID
                            )
                        }
                    }
                } header: {
                    Text("Recent meetings")
                }
            }
            .searchable(text: $search, prompt: "Search meetings")
            .navigationTitle("Follows up on")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    PrepCloseButton { dismiss() }
                }
            }
        }
    }

    private func optionRow(title: String, subtitle: String?, selected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(PrepStyle.secondaryText)
                }
            }
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Colors.manentAccent)
            }
        }
        .contentShape(Rectangle())
    }
}
