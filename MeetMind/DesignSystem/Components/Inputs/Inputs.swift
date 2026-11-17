import SwiftUI

// MARK: - Custom Text Field
public struct CustomTextField: View {
    public let placeholder: String
    @Binding public var text: String
    public var icon: String? = nil
    public var isSecure: Bool = false
    
    public init(placeholder: String, text: Binding<String>, icon: String? = nil, isSecure: Bool = false) {
        self.placeholder = placeholder
        self._text = text
        self.icon = icon
        self.isSecure = isSecure
    }
    
    public var body: some View {
        HStack(spacing: Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(Spacing.md)
        .background(Theme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.Radius.md, style: .continuous)
                .stroke(Theme.Colors.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Search Bar
public struct SearchBar: View {
    @Binding public var text: String
    public var placeholder: String = "Search meetings, transcripts, action items..."
    public var onCommit: (() -> Void)? = nil
    
    public init(text: Binding<String>, placeholder: String = "Search meetings, transcripts, action items...", onCommit: (() -> Void)? = nil) {
        self._text = text
        self.placeholder = placeholder
        self.onCommit = onCommit
    }
    
    public var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.textSecondary)
                .font(.system(size: 16))
            
            TextField(placeholder, text: $text)
                .font(Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .autocorrectionDisabled()
                .onSubmit { onCommit?() }
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(Capsule())
    }
}

// MARK: - Filter Chip
public struct FilterChip: View {
    public let title: String
    public let isSelected: Bool
    public var count: Int? = nil
    public let onSelect: () -> Void
    
    public init(title: String, isSelected: Bool, count: Int? = nil, onSelect: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.count = count
        self.onSelect = onSelect
    }
    
    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                if let count {
                    Text("\(count)")
                        .font(Typography.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.white.opacity(0.25) : Theme.Colors.cardBorder)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? Color.white : Theme.Colors.textPrimary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? Theme.Colors.primarySlate : Color(uiColor: .tertiarySystemFill))
            .clipShape(Capsule())
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}
