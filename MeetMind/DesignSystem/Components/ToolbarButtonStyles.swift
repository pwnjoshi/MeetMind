import SwiftUI
import UIKit

/// Round accent confirm button for navigation-bar toolbars (Save, Done, Continue).
///
/// On iOS 26 the toolbar already draws a glass circle around every item, so a bordered
/// circle inside it showed two circles. There the button only gets the prominent glass
/// tint. Before iOS 26 it draws its own single prominent circle.
struct ToolbarConfirmButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .tint(Theme.Colors.manentAccent)
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    private func legacy(_ content: Content) -> some View {
        content
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
    }
}

/// Prominent text button (for example "Done") inside a toolbar. On iOS 26 the toolbar draws
/// the glass capsule, so the button only gets the tint. Before iOS 26 it draws one capsule.
struct ToolbarProminentTextButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .tint(Theme.Colors.manentAccent)
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    private func legacy(_ content: Content) -> some View {
        content
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
    }
}

/// True when the navigation toolbar draws its own glass behind each item (iOS 26+).
enum ToolbarGlass {
    static var isSystemProvided: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }
}

extension View {
    /// Prominent text button inside a toolbar, with a single capsule on every OS.
    func toolbarProminentTextButtonStyle() -> some View {
        modifier(ToolbarProminentTextButtonStyle())
    }

    /// Prominent round confirm button inside a toolbar, with a single circle on every OS.
    func toolbarConfirmButtonStyle() -> some View {
        modifier(ToolbarConfirmButtonStyle())
    }
}

// MARK: - Page header (Figma A2 Meetings, F1 Actions)

/// Large title on the same row as separate round buttons at the trailing edge. Used by the
/// Meetings and Actions pages instead of the system toolbar so both pages place their
/// controls identically on every iOS version.
struct ManentPageHeader<Trailing: View>: View {
    let title: String
    private let trailing: Trailing

    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// 40 pt circular glass (iOS 26) or white (earlier) background for a header button label.
struct HeaderCircleModifier: ViewModifier {
    static let diameter: CGFloat = 40

    @ViewBuilder
    func body(content: Content) -> some View {
        let base = content
            .frame(width: Self.diameter, height: Self.diameter)
            .contentShape(Circle())
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            base.glassEffect(.regular.interactive(), in: Circle())
        } else {
            fallback(base)
        }
        #else
        fallback(base)
        #endif
    }

    private func fallback<V: View>(_ view: V) -> some View {
        view
            .background(Circle().fill(Color(uiColor: .secondarySystemGroupedBackground)))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
    }
}

extension View {
    /// Wraps a header button label in its own 40 pt circle.
    func headerCircle() -> some View {
        modifier(HeaderCircleModifier())
    }
}

/// Profile avatar for the page header: the saved photo, the user's initials once a real name
/// is set, otherwise the grey person-in-circle placeholder from the design.
struct ProfileAvatarView: View {
    let profile: UserProfile?
    var size: CGFloat = HeaderCircleModifier.diameter

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
    }

    @ViewBuilder
    private var content: some View {
        if let data = profile?.avatarImageData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let profile, Self.hasRealName(profile.name) {
            ZStack {
                Theme.Colors.manentAccent
                Text(profile.initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            }
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(uiColor: .systemGray6), Color(uiColor: .systemGray3))
        }
    }

    static func hasRealName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != UserProfile.defaultLocalName && trimmed != "MeetMind User"
    }
}

/// Profile button for the page header. Opens Settings on the given tab's stack.
struct ProfileHeaderButton: View {
    let tab: TabIdentifier
    @Environment(NavigationRouter.self) private var router
    @Environment(SettingsViewModel.self) private var settings: SettingsViewModel?

    var body: some View {
        Button {
            router.navigate(to: .settings, in: tab)
        } label: {
            ProfileAvatarView(profile: settings?.userProfile)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and settings")
    }
}