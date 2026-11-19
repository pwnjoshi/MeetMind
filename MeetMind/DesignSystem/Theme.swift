import SwiftUI

/// MeetMind Authoritative Design System Theme Tokens
/// Extracted directly from Figma Specification (Node 8:2)
public enum Theme {
    
    // MARK: - Brand Core Colors
    public struct Colors {
        public static let manentAccent = Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 0.62, green: 0.59, blue: 1, alpha: 1)
            }
            return UIColor(red: 79.0 / 255, green: 70.0 / 255, blue: 229.0 / 255, alpha: 1)
        })
        /// Primary brand slate dark forest green (#1E2E28)
        public static let primarySlate = Color(hex: 0x1E2E28)
        
        /// Secondary header slate (#243830)
        public static let secondarySlate = Color(hex: 0x243830)
        
        /// Warm amber for meeting setup, warnings, and starred items (#F59E0B)
        public static let warmAmber = Color(hex: 0xF59E0B)
        
        /// Soft amber fill for cards and badges (#FEF3C7)
        public static let warmAmberLight = Color(hex: 0xFEF3C7)
        
        /// Live blue for streaming audio and speech transcription (#3B82F6)
        public static let liveBlue = Color(hex: 0x3B82F6)
        
        /// Light sky blue fill for audio cards and streaming backgrounds (#E0F2FE)
        public static let liveBlueLight = Color(hex: 0xE0F2FE)
        
        /// AI purple for intelligence summaries, decisions, and Ask AI (#8B5CF6)
        public static let aiPurple = Color(hex: 0x8B5CF6)
        
        /// Deep violet accent (#7C3AED)
        public static let aiPurpleDark = Color(hex: 0x7C3AED)
        
        /// Light lavender fill for AI cards (#EDE9FE)
        public static let aiPurpleLight = Color(hex: 0xEDE9FE)
        
        /// Mint green for completed states and success triggers (#10B981)
        public static let mintGreen = Color(hex: 0x10B981)
        
        /// Darker emerald accent (#059669)
        public static let mintGreenDark = Color(hex: 0x059669)
        
        /// Light sage fill for completed badges (#D1FAE5)
        public static let mintGreenLight = Color(hex: 0xD1FAE5)
        
        /// Coral red for active recording stop and destructive actions (#EF4444)
        public static let coralRed = Color(hex: 0xEF4444)
        
        /// Deep crimson accent (#DC2626)
        public static let coralRedDark = Color(hex: 0xDC2626)
        
        /// Light pink/coral fill for recording HUD and discard alerts (#FEE2E2)
        public static let coralRedLight = Color(hex: 0xFEE2E2)
        
        // MARK: - Adaptive Surfaces
        public static var background: Color {
            Color(uiColor: .systemBackground)
        }
        
        public static var secondaryBackground: Color {
            Color(uiColor: .secondarySystemBackground)
        }
        
        public static var cardBackground: Color {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
        
        public static var cardBorder: Color {
            Color(uiColor: .separator)
        }
        
        // MARK: - Text Hierarchy
        public static var textPrimary: Color {
            Color(uiColor: .label)
        }
        
        public static var textSecondary: Color {
            Color(uiColor: .secondaryLabel)
        }
        
        public static var textTertiary: Color {
            Color(uiColor: .tertiaryLabel)
        }
    }
}

// MARK: - Color Hex Initializer
public extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex & 0xFF0000) >> 16) / 255.0
        let green = Double((hex & 0x00FF00) >> 8) / 255.0
        let blue = Double(hex & 0x0000FF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
    
    init(hex: String) {
        self.init(hexString: hex)
    }
    
    init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    static var theme: Theme.Colors.Type {
        Theme.Colors.self
    }
}
