import SwiftUI

extension Color {
    /// 0xRRGGBB, used for the Figma tile colours on the Profile page.
    init(settingsHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Rounded colored icon tile used by v5 Profile rows (30 pt, 8 pt radius).
/// Pass `label` to expose the tile to VoiceOver; rows that combine their content leave it nil.
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
            .frame(width: 30, height: 30)
            .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Row label: icon tile, title, and an optional secondary value on the trailing side.
struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconTile(systemImage: systemImage, color: color)
            Text(title).font(.body).foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let value, !value.isEmpty {
                Text(value)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + 42 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value ?? ""))
    }
}

/// Row whose trailing value opens a menu (up/down chevrons), as MoM Format and Audio Quality do in Figma.
struct SettingsMenuRow<MenuContent: View>: View {
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
            HStack(spacing: 12) {
                SettingsIconTile(systemImage: systemImage, color: color)
                Text(title).font(.body).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + 42 }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }
}

/// Soft gradient banner used at the top of Vidur, Contacts and similar screens.
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

/// Small stat tile for the profile header.
struct SettingsStatTile: View {
    let value: String
    let label: String
    var tint: Color = Theme.Colors.manentAccent

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
