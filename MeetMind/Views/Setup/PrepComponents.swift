import SwiftUI

/// Shared building blocks for the "Prepare a meeting" screens.
enum PrepStyle {
    static var background: Color { Color(uiColor: .systemGroupedBackground) }
    static var secondaryText: Color { Color(uiColor: .secondaryLabel) }
}

/// White rounded container used for inset-grouped sections.
struct PrepCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Small grey section caption ("People", "Suggestions").
struct PrepSectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(PrepStyle.secondaryText)
            .padding(.horizontal, 12)
    }
}

/// Round accent check button used to confirm a sheet or form.
struct PrepConfirmButton: View {
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .semibold))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(Theme.Colors.manentAccent)
        .disabled(!isEnabled)
        .accessibilityLabel("Done")
    }
}

/// Round neutral close/back button.
struct PrepCloseButton: View {
    var systemName: String = "xmark"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(.primary)
        .accessibilityLabel(systemName == "xmark" ? "Close" : "Back")
    }
}

/// Initials avatar used in people lists.
struct PrepAvatar: View {
    let name: String
    let initials: String
    let colorHex: String

    var body: some View {
        Text(initials)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Color(hex: colorHex), in: Circle())
            .accessibilityHidden(true)
    }
}

/// One row of a people list: avatar, name, email.
struct PrepPersonRow: View {
    let speaker: Speaker
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            PrepAvatar(name: speaker.name, initials: speaker.initials, colorHex: speaker.avatarColorHex)
            VStack(alignment: .leading, spacing: 2) {
                Text(speaker.name).foregroundStyle(.primary)
                if let email = speaker.email, !email.isEmpty {
                    Text(email).font(.subheadline).foregroundStyle(PrepStyle.secondaryText)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).foregroundStyle(PrepStyle.secondaryText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

/// Parsing for the numeric time entry popover ("530" or "5:30" plus AM/PM).
enum PrepTimeParser {
    static func parse(_ text: String) -> (hour: Int, minute: Int)? {
        let digits = text.filter { $0.isNumber }
        guard digits.count >= 1, digits.count <= 4 else { return nil }
        let hourText: String
        let minuteText: String
        switch digits.count {
        case 1, 2:
            hourText = digits
            minuteText = "0"
        case 3:
            hourText = String(digits.prefix(1))
            minuteText = String(digits.suffix(2))
        default:
            hourText = String(digits.prefix(2))
            minuteText = String(digits.suffix(2))
        }
        guard let hour = Int(hourText), let minute = Int(minuteText),
              (1...12).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    /// Replaces the time of day of `date`.
    static func apply(hour12: Int, minute: Int, isPM: Bool, to date: Date, calendar: Calendar = .current) -> Date {
        let hour24 = (hour12 % 12) + (isPM ? 12 : 0)
        return calendar.date(bySettingHour: hour24, minute: minute, second: 0, of: date) ?? date
    }

    /// Digits such as "530" and the PM flag for display in the entry field.
    static func fields(for date: Date, calendar: Calendar = .current) -> (digits: String, isPM: Bool) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour24 = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return (String(format: "%d%02d", hour12, minute), hour24 >= 12)
    }
}

/// Numeric time entry with an AM/PM switch and a Done button.
struct PrepTimeEntryView: View {
    @Binding var date: Date
    var onDone: () -> Void

    @State private var digits: String = ""
    @State private var isPM: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            TextField("5:30", text: $digits)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 40, weight: .semibold))
                .focused($focused)
                .accessibilityLabel("Time")
            Picker("AM or PM", selection: $isPM) {
                Text("AM").tag(false)
                Text("PM").tag(true)
            }
            .pickerStyle(.segmented)
            Button("Done") {
                if let parsed = PrepTimeParser.parse(digits) {
                    date = PrepTimeParser.apply(hour12: parsed.hour, minute: parsed.minute, isPM: isPM, to: date)
                }
                onDone()
            }
            .fontWeight(.medium)
            .tint(Theme.Colors.manentAccent)
        }
        .padding(16)
        .frame(width: 240)
        .onAppear {
            let current = PrepTimeParser.fields(for: date)
            digits = current.digits
            isPM = current.isPM
            focused = true
        }
    }
}

/// Grey capsule that edits the date or the time of a Date in a popover.
struct PrepDatePill: View {
    enum Kind { case date, time }

    let kind: Kind
    @Binding var date: Date
    @State private var showsPopover = false

    var body: some View {
        Button {
            showsPopover = true
        } label: {
            Text(label)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsPopover) {
            Group {
                switch kind {
                case .date:
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(Theme.Colors.manentAccent)
                        .padding(12)
                        .frame(width: 340)
                case .time:
                    PrepTimeEntryView(date: $date) { showsPopover = false }
                }
            }
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(kind == .date ? "Date" : "Time")
        .accessibilityValue(label)
    }

    private var label: String {
        switch kind {
        case .date: return date.formatted(.dateTime.day().month(.abbreviated).year())
        case .time: return date.formatted(date: .omitted, time: .shortened)
        }
    }
}

/// Sheet with a single text field and a suggestion list (Meeting title, Meeting agenda).
struct PrepTextEntrySheet: View {
    let title: String
    let placeholder: String
    let suggestionsTitle: String
    let suggestions: [String]
    var multiline: Bool = false
    @Binding var text: String

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @FocusState private var focused: Bool

    init(title: String, placeholder: String, suggestionsTitle: String, suggestions: [String], multiline: Bool = false, text: Binding<String>) {
        self.title = title
        self.placeholder = placeholder
        self.suggestionsTitle = suggestionsTitle
        self.suggestions = suggestions
        self.multiline = multiline
        self._text = text
        self._draft = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PrepCard {
                        TextField(placeholder, text: $draft, axis: multiline ? .vertical : .horizontal)
                            .lineLimit(multiline ? 3...10 : 1...1)
                            .focused($focused)
                            .submitLabel(multiline ? .return : .done)
                            .padding(16)
                    }
                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            PrepSectionLabel(text: suggestionsTitle)
                            PrepCard {
                                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                                    Button {
                                        draft = suggestion
                                    } label: {
                                        Text(suggestion)
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(16)
                                    }
                                    .buttonStyle(.plain)
                                    if index < suggestions.count - 1 { Divider().padding(.leading, 16) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(PrepStyle.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    PrepCloseButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    PrepConfirmButton {
                        text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                }
            }
            .onAppear { focused = true }
        }
    }
}
