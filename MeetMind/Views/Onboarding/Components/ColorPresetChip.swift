import SwiftUI

/// Preset avatar color selector chip
public struct ColorPresetChip: View {
    public let colorHex: String
    public let isSelected: Bool
    public let onSelect: () -> Void
    
    public init(colorHex: String, isSelected: Bool, onSelect: @escaping () -> Void) {
        self.colorHex = colorHex
        self.isSelected = isSelected
        self.onSelect = onSelect
    }
    
    public var body: some View {
        Button(action: onSelect) {
            ZStack {
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 36, height: 36)
                
                if isSelected {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Color option \(colorHex)")
    }
}
