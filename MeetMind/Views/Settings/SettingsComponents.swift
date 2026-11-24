import SwiftUI
import UIKit

extension Color {
    /// 0xRRGGBB, used only to define the exported Profile palette.
    init(settingsHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Colors and dimensions exported from Figma H1. Semantic surfaces preserve the H1
/// light appearance while following iOS in Dark Mode and increased-contrast modes.
enum ProfilePalette {
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)       // H1 #F2F2F7
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground) // H1 #FFFFFF
    static let separator = Color(uiColor: .separator)
    static let primaryText = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)                    // H1 #8A8A8E
    static let sectionHeader = Color(uiColor: .secondaryLabel)

    static let accent = Color(settingsHex: 0x4F46E5)
    static let avatar = Color(settingsHex: 0x5E5CE6)
    static let teal = Color(settingsHex: 0x30B0C7)
    static let indigo = Color(settingsHex: 0x5856D6)
    static let orange = Color(settingsHex: 0xFF9500)
    static let blue = Color(settingsHex: 0x007AFF)
    static let pink = Color(settingsHex: 0xFF2D55)
    static let red = Color(settingsHex: 0xFF3B30)
    static let gray = Color(settingsHex: 0x8E8E93)
    static let green = Color(settingsHex: 0x34C759)

    static let iconTileSize: CGFloat = 30
    static let iconTileCornerRadius: CGFloat = 8
    static let cardCornerRadius: CGFloat = 26
    static let sectionSpacing: CGFloat = 26
}

extension View {
    /// Applies the H1 card surface and separator to every row in a Profile section.
    func profileSectionRows() -> some View {
        listRowBackground(ProfilePalette.cardBackground)
            .listRowSeparatorTint(ProfilePalette.separator)
    }
}

/// Pure profile formatting shared by the header, editor preview, fixture, and unit tests.
enum ProfileFormatting {
    static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidName(_ value: String) -> Bool {
        !cleaned(value).isEmpty
    }

    static func shownOnMinutes(name: String, role: String) -> String {
        let cleanedName = cleaned(name)
        let cleanedRole = cleaned(role)
        if cleanedName.isEmpty { return "Your name" }
        if cleanedRole.isEmpty { return cleanedName }
        return "\(cleanedName), \(cleanedRole)"
    }

    static func recordedDurationText(seconds: TimeInterval) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3_600
        if hours >= 1 { return "\(Int(hours.rounded())) h" }
        return "\(Int((safeSeconds / 60).rounded())) m"
    }
}

struct ProfileStatistics {
    let meetings: String
    let recorded: String
    let openActions: String
}

/// Rounded colored icon tile used by H1 Profile rows (30 pt, 8 pt radius).
/// Pass `label` to expose the tile to VoiceOver; rows otherwise treat it as decoration.
struct SettingsIconTile: View {
    let systemImage: String
    let color: Color
    var label: String?

    var body: some View {
        if let label {
            tile.accessibilityLabel(label)
        } else {
            tile.accessibilityHidden(true)
        }
    }

    private var tile: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: ProfilePalette.iconTileSize, height: ProfilePalette.iconTileSize)
            .background(
                color,
                in: RoundedRectangle(
                    cornerRadius: ProfilePalette.iconTileCornerRadius,
                    style: .continuous
                )
            )
    }
}

/// Row label that keeps short H1 content on one line and moves a long value under
/// the title, aligned after the icon. NavigationLink owns the trailing chevron.
struct SettingsRowLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let systemImage: String
    let color: Color
    var value: String?

    private var hasValue: Bool {
        guard let value else { return false }
        return !value.isEmpty
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                verticalLayout
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalLayout
                    verticalLayout
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + 42 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value ?? ""))
    }

    private var horizontalLayout: some View {
        HStack(spacing: 12) {
            SettingsIconTile(systemImage: systemImage, color: color)
            Text(title)
                .font(.body)
                .foregroundStyle(ProfilePalette.primaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            Spacer(minLength: 8)
            if let value, hasValue {
                Text(value)
                    .font(.body)
                    .foregroundStyle(ProfilePalette.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
    }

    private var verticalLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsIconTile(systemImage: systemImage, color: color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(ProfilePalette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)
                if let value, hasValue {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(ProfilePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
        }
    }
}

/// Row whose value opens a menu. The fallback keeps the menu indicator in its own
/// trailing column, so long values can never collide with it.
struct SettingsMenuRow<MenuContent: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let systemImage: String
    let color: Color
    let value: String
    private let menuContent: MenuContent

    init(title: String, systemImage: String, color: Color, value: String,
         @ViewBuilder menuContent: () -> MenuContent) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.value = value
        self.menuContent = menuContent()
    }

    var body: some View {
        Menu {
            menuContent
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    verticalLayout
                } else {
                    ViewThatFits(in: .horizontal) {
                        horizontalLayout
                        verticalLayout
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + 42 }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }

    private var menuIndicator: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(ProfilePalette.secondaryText)
            .accessibilityHidden(true)
    }

    private var horizontalLayout: some View {
        HStack(spacing: 12) {
            SettingsIconTile(systemImage: systemImage, color: color)
            Text(title)
                .font(.body)
                .foregroundStyle(ProfilePalette.primaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            Spacer(minLength: 8)
            Text(value)
                .font(.body)
                .foregroundStyle(ProfilePalette.secondaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            menuIndicator
        }
    }

    private var verticalLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsIconTile(systemImage: systemImage, color: color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(ProfilePalette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(ProfilePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            menuIndicator.padding(.top, 7)
        }
    }
}

struct ProfileSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(ProfilePalette.sectionHeader)
            .textCase(.uppercase)
    }
}

/// Soft gradient banner used at the top of Contacts and similar screens.
struct SettingsBanner: View {
    let title: String
    let detail: String
    var systemImage: String = "checkmark.circle.fill"
    var tint: Color = Theme.Colors.mintGreenDark

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                Text(detail).font(.footnote).foregroundStyle(tint.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Small stat tile for the Profile header. A caller provides a width only when the
/// accessibility layout scrolls horizontally.
struct SettingsStatTile: View {
    let value: String
    let label: String
    var tint: Color = ProfilePalette.accent
    var width: CGFloat?

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(ProfilePalette.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: width == nil ? .infinity : nil, minHeight: 72)
        .frame(width: width)
        .background(
            ProfilePalette.cardBackground,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// Local profile avatar used on Profile and H5. Figma uses a 5E5CE6 initials fill.
struct SettingsProfileAvatar: View {
    let profile: UserProfile
    let size: CGFloat

    var body: some View {
        Group {
            if let data = profile.avatarImageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(profile.initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ProfilePalette.avatar)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ProfilePalette.separator.opacity(0.35), lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.08), radius: 5, y: 2)
    }
}
