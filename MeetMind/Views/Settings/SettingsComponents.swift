import SwiftUI

/// Rounded colored icon tile used by v5 Profile rows.
struct SettingsIconTile: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
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
            Text(title).font(.subheadline).foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let value, !value.isEmpty {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .combine)
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
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
