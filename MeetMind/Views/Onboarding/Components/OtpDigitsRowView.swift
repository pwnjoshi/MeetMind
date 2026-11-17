import SwiftUI

/// 6 discrete OTP boxes matching Figma node 976:721
public struct OtpDigitsRowView: View {
    public let digits: [String]
    
    public init(digits: [String]) {
        self.digits = digits
    }
    
    public var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<6, id: \.self) { idx in
                let char = digits.indices.contains(idx) ? digits[idx] : ""
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: .systemBackground))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#DFE4EF"), lineWidth: 1.5))
                    Text(char)
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(uiColor: .label))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 64)
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}
