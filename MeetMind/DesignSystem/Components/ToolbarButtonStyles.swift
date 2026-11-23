import SwiftUI

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

/// Neutral round toolbar button (close, back, filter). On iOS 26 it is left plain so the
/// system toolbar glass is the only circle. Before iOS 26 it draws one bordered circle.
struct ToolbarNeutralButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.tint(.primary)
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    private func legacy(_ content: Content) -> some View {
        content
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(.primary)
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

    /// Neutral round button inside a toolbar, with a single circle on every OS.
    func toolbarNeutralButtonStyle() -> some View {
        modifier(ToolbarNeutralButtonStyle())
    }
}
