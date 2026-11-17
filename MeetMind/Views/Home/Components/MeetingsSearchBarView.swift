import SwiftUI

/// Search and filter bar matching Figma node 161:777
public struct MeetingsSearchBarView: View {
    @Binding public var text: String
    public let onFilterTap: () -> Void
    
    public init(text: Binding<String>, onFilterTap: @escaping () -> Void = {}) {
        self._text = text
        self.onFilterTap = onFilterTap
    }
    
    public var body: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "#8E8E93"))
                
                TextField("Search meetings", text: $text)
                    .font(Typography.body)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                
                if !text.isEmpty {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "#8E8E93"))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(hex: "#F0F3FA"))
            .clipShape(Capsule())
            
            Button(action: onFilterTap) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "#0088FF"))
                    .frame(width: 44, height: 44)
                    .background(Color(hex: "#F0F3FA"))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Filter meetings")
        }
    }
}
