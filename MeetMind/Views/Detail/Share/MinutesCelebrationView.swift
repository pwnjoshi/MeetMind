import SwiftUI

/// Steps of the "Minutes Sent" reveal (Figma B9 animating into B10 settled). Each step builds on the one before.
enum MinutesSentStage: Int, Comparable {
    case initial
    case halo
    case disc
    case check
    case avatars
    case done

    static func < (lhs: MinutesSentStage, rhs: MinutesSentStage) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Hero artwork: a soft purple halo, a green disc with a drawn-on check, and recipient initials floating around it.
/// Geometry follows the Figma frame (112 pt disc, 48 pt avatars at the four corners).
struct MinutesCelebrationView: View {
    let recipients: [SharedMinutesRecipient]
    let stage: MinutesSentStage
    let animated: Bool

    private static let avatarOffsets: [CGSize] = [
        CGSize(width: -142, height: -70), CGSize(width: 114, height: -70),
        CGSize(width: -121, height: 92), CGSize(width: 96, height: 93)
    ]

    private static let green = Color(red: 0.204, green: 0.78, blue: 0.349)

    var body: some View {
        ZStack {
            halo
            avatars
            disc
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .accessibilityHidden(true)
    }

    private var haloVisible: Bool { stage >= .halo }
    private var discVisible: Bool { stage >= .disc }
    private var checkVisible: Bool { stage >= .check }

    private var halo: some View {
        Circle()
            .fill(Theme.Colors.manentAccent)
            .frame(width: 200, height: 200)
            .blur(radius: 38)
            .opacity(haloVisible ? 0.32 : 0)
            .scaleEffect(haloVisible ? 1 : 0.6)
            .animation(animated ? .easeOut(duration: 0.7) : nil, value: haloVisible)
    }

    private var disc: some View {
        ZStack {
            Circle()
                .fill(Self.green)
                .frame(width: 112, height: 112)
                .shadow(color: Self.green.opacity(0.35), radius: 14, y: 10)
            MinutesCheckShape()
                .trim(from: 0, to: checkVisible ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                .frame(width: 62, height: 48)
                .animation(animated ? .easeOut(duration: 0.4) : nil, value: checkVisible)
        }
        .scaleEffect(discVisible ? 1 : 0.3)
        .opacity(discVisible ? 1 : 0)
        .animation(animated ? .spring(response: 0.5, dampingFraction: 0.6) : nil, value: discVisible)
    }

    private var avatars: some View {
        let shown = Array(recipients.prefix(Self.avatarOffsets.count).enumerated())
        return ZStack {
            ForEach(shown, id: \.offset) { entry in
                MinutesAvatarBubble(recipient: entry.element,
                                    index: entry.offset,
                                    target: Self.avatarOffsets[entry.offset],
                                    visible: stage >= .avatars,
                                    animated: animated)
            }
        }
    }
}

/// Recipient initials bubble that springs out from behind the disc, one after another.
struct MinutesAvatarBubble: View {
    let recipient: SharedMinutesRecipient
    let index: Int
    let target: CGSize
    let visible: Bool
    let animated: Bool

    var body: some View {
        Text(MeetingRecordInitials.initials(recipient.name))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(Color(hex: recipient.colorHex), in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.10), radius: 6, y: 3)
            .scaleEffect(visible ? 1 : 0.2)
            .offset(visible ? target : .zero)
            .opacity(visible ? 1 : 0)
            .animation(animated ? spring : nil, value: visible)
    }

    private var spring: Animation {
        .spring(response: 0.5, dampingFraction: 0.62).delay(0.09 * Double(index))
    }
}

/// Check mark path in a 62 x 48 box, matching the Figma "Checkmark" vector.
struct MinutesCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.92))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.98, y: rect.minY + rect.height * 0.04))
        return path
    }
}
