import SwiftUI

public enum Spacing {
    /// 2pt - micro gap, badge inner spacing
    public static let xxs: CGFloat = 2
    
    /// 4pt - tight elements, icon spacing
    public static let xs: CGFloat = 4
    
    /// 8pt - compact padding, chip vertical padding
    public static let sm: CGFloat = 8
    
    /// 12pt - standard stack spacing, text field inner padding
    public static let md: CGFloat = 12
    
    /// 16pt - default screen edge margin, card content padding
    public static let lg: CGFloat = 16
    
    /// 24pt - section separation, modal header margin
    public static let xl: CGFloat = 24
    
    /// 32pt - major vertical spacing, hero offset
    public static let xxl: CGFloat = 32
    
    /// 48pt - empty state vertical spacing
    public static let xxxl: CGFloat = 48
    
    /// Card content padding alias (16pt)
    public static let cardPadding: CGFloat = Spacing.lg
    
    /// Card corner radius alias (16pt)
    public static let cardCornerRadius: CGFloat = Spacing.Radius.lg
    
    // MARK: - Corner Radii
    public struct Radius {
        /// 6pt - tiny badges and tags
        public static let sm: CGFloat = 6
        
        /// 10pt - standard buttons, input fields
        public static let md: CGFloat = 10
        
        /// 16pt - meeting cards, summary cards, action cards
        public static let lg: CGFloat = 16
        
        /// 24pt - modal sheets, floating containers
        public static let xl: CGFloat = 24
        
        /// 999pt - full pill capsule badges and FABs
        public static let pill: CGFloat = 999
    }
    
    // MARK: - Shadows & Elevation
    public struct Elevation {
        public static let card = ShadowConfig(
            color: Color.black.opacity(0.06),
            radius: 8,
            x: 0,
            y: 2
        )
        
        public static let floating = ShadowConfig(
            color: Color.black.opacity(0.14),
            radius: 16,
            x: 0,
            y: 6
        )
        
        public static let recordingGlow = ShadowConfig(
            color: Theme.Colors.coralRed.opacity(0.35),
            radius: 12,
            x: 0,
            y: 0
        )
    }
}

public struct ShadowConfig: Sendable {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat
    
    public init(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

public extension View {
    func applyShadow(_ shadow: ShadowConfig) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
