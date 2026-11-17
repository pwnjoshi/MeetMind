import SwiftUI

public enum Typography {
    
    // MARK: - Display & Screen Titles
    public static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
    public static let title1 = Font.system(size: 28, weight: .bold, design: .default)
    public static let title2 = Font.system(size: 22, weight: .bold, design: .default)
    public static let title3 = Font.system(size: 20, weight: .semibold, design: .default)
    
    // MARK: - Headers & Cards
    public static let headline = Font.system(size: 17, weight: .semibold, design: .default)
    public static let body = Font.system(size: 16, weight: .regular, design: .default)
    public static let callout = Font.system(size: 15, weight: .medium, design: .default)
    public static let subheadline = Font.system(size: 14, weight: .regular, design: .default)
    
    // MARK: - Captions & Badges
    public static let footnote = Font.system(size: 13, weight: .medium, design: .default)
    public static let caption = Font.system(size: 12, weight: .semibold, design: .default)
    public static let caption2 = Font.system(size: 11, weight: .regular, design: .default)
    
    // MARK: - Numeric & Timecodes
    public static let timer = Font.system(size: 36, weight: .bold, design: .monospaced)
    public static let timecode = Font.system(size: 14, weight: .semibold, design: .monospaced)
    public static let speedIndicator = Font.system(size: 13, weight: .bold, design: .rounded)
}

public extension Font {
    static var meetMind: Typography.Type {
        Typography.self
    }
}

// MARK: - Text Modifiers for Standard Styling
public struct HeadlineModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(Typography.headline)
            .foregroundStyle(Theme.Colors.textPrimary)
    }
}

public struct BodyTextModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(Typography.body)
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineSpacing(4)
    }
}

public struct SubtextModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(Typography.subheadline)
            .foregroundStyle(Theme.Colors.textSecondary)
    }
}

public extension View {
    func meetingHeadline() -> some View {
        modifier(HeadlineModifier())
    }
    
    func meetingBody() -> some View {
        modifier(BodyTextModifier())
    }
    
    func meetingSubtext() -> some View {
        modifier(SubtextModifier())
    }
}
