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
// MARK: - Filter Chip
