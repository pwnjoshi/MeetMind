import SwiftUI

// MARK: - Important glow
//
// Meetings marked Important (`Meeting.isFavorite`) get a soft multi-colour glow that
// travels around the card border. The gradient is one AngularGradient rotated by an angle
// derived from the timeline date, so the only per-frame state is that angle. Reduce Motion
// renders the same gradient without rotation.

enum ImportantGlowPalette {
    /// Blue, purple, pink, orange and a little cyan, closed back to blue so the loop is seamless.
    static let colors: [Color] = [
        Color(red: 0.25, green: 0.52, blue: 1.00),
        Color(red: 0.62, green: 0.36, blue: 0.96),
        Color(red: 1.00, green: 0.36, blue: 0.66),
        Color(red: 1.00, green: 0.60, blue: 0.26),
        Color(red: 0.30, green: 0.82, blue: 0.95),
        Color(red: 0.25, green: 0.52, blue: 1.00)
    ]

    /// Seconds for one full turn of the gradient.
    static let secondsPerTurn: Double = 6
}

/// Supplies the current gradient angle. Animated unless Reduce Motion is on.
private struct ImportantAngleReader<Content: View>: View {
    let animated: Bool
    let content: (Angle) -> Content

    init(animated: Bool, @ViewBuilder content: @escaping (Angle) -> Content) {
        self.animated = animated
        self.content = content
    }

    var body: some View {
        if animated {
            TimelineView(.animation) { context in
                content(Self.angle(at: context.date))
            }
        } else {
            content(.degrees(0))
        }
    }

    private static func angle(at date: Date) -> Angle {
        let period = ImportantGlowPalette.secondsPerTurn
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return .degrees(phase * 360)
    }
}

struct ImportantGlowBorder: ViewModifier {
    let isActive: Bool
    let cornerRadius: CGFloat
    var lineWidth: CGFloat = 2.5
    var glowRadius: CGFloat = 12
    var glowOpacity: Double = 0.38
    /// Insets the stroke from the view's edge (used for rows drawn inside a larger card).
    var inset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isActive {
            content
                .background {
                    if glowRadius > 0 {
                        ImportantAngleReader(animated: !reduceMotion) { angle in
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(gradient(angle), lineWidth: lineWidth * 2)
                                .blur(radius: glowRadius)
                                .opacity(glowOpacity)
                                .padding(inset)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                .overlay {
                    ImportantAngleReader(animated: !reduceMotion) { angle in
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(gradient(angle), lineWidth: lineWidth)
                            .padding(inset)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
        } else {
            content
        }
    }

    private func gradient(_ angle: Angle) -> AngularGradient {
        AngularGradient(colors: ImportantGlowPalette.colors, center: .center, angle: angle)
    }
}

extension View {
    /// Adds the moving multi-colour Important glow around a card when `isActive` is true.
    /// Apply it after the card's clip shape so the outer glow is not clipped.
    func importantGlowBorder(
        _ isActive: Bool,
        cornerRadius: CGFloat,
        lineWidth: CGFloat = 2.5,
        glowRadius: CGFloat = 12,
        glowOpacity: Double = 0.38,
        inset: CGFloat = 0
    ) -> some View {
        modifier(ImportantGlowBorder(
            isActive: isActive,
            cornerRadius: cornerRadius,
            lineWidth: lineWidth,
            glowRadius: glowRadius,
            glowOpacity: glowOpacity,
            inset: inset
        ))
    }
}

// MARK: - Badge

/// Small star (and optional "Important" label) shown on Important meetings.
struct ImportantBadge: View {
    enum Style {
        /// Gradient star and label on a light surface.
        case standard
        /// White star and label on a dark or coloured surface.
        case onDark
    }

    var style: Style = .standard
    /// Star only, for rows where a text label would not fit.
    var iconOnly = false

    var body: some View {
        Group {
            if iconOnly {
                star
            } else {
                HStack(spacing: 4) {
                    star
                    Text("Important")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(style == .onDark ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    style == .onDark ? Color.white.opacity(0.2) : Color(uiColor: .tertiarySystemFill),
                    in: Capsule()
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Important")
    }

    private var star: some View {
        Image(systemName: "star.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(starStyle)
    }

    private var starStyle: AnyShapeStyle {
        if style == .onDark { return AnyShapeStyle(Color.white) }
        return AnyShapeStyle(LinearGradient(
            colors: ImportantGlowPalette.colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
    }
}
