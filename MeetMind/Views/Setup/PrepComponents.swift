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

/// Round accent check button used to confirm a sheet or form. On iOS 26 the toolbar
/// already draws the glass; only the prominent tint is added, never a second circle.
struct PrepConfirmButton: View {
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        styled(Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .semibold))
        })
        .disabled(!isEnabled)
        .accessibilityLabel("Done")
    }

    @ViewBuilder
    private func styled<Label: View>(_ button: Button<Label>) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            button.buttonStyle(.glassProminent).tint(Theme.Colors.manentAccent)
        } else {
            button.buttonStyle(.borderedProminent).buttonBorderShape(.circle).tint(Theme.Colors.manentAccent)
        }
        #else
        button.buttonStyle(.borderedProminent).buttonBorderShape(.circle).tint(Theme.Colors.manentAccent)
        #endif
    }
}

/// Round neutral close/back button. On iOS 26 the toolbar supplies the glass circle, so
/// the button itself is plain; drawing a bordered circle inside it showed two circles.
struct PrepCloseButton: View {
    var systemName: String = "xmark"
    let action: () -> Void

    var body: some View {
        styled(Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
        })
        .accessibilityLabel(systemName == "xmark" ? "Close" : "Back")
    }

    @ViewBuilder
    private func styled<Label: View>(_ button: Button<Label>) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            button.tint(.primary)
        } else {
            button.buttonStyle(.bordered).buttonBorderShape(.circle).tint(.primary)
        }
        #else
        button.buttonStyle(.bordered).buttonBorderShape(.circle).tint(.primary)
        #endif
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
