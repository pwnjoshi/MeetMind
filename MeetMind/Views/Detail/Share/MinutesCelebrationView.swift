import SwiftUI

/// Phases of the post-share screen. Figma "Delivery status" (161:1912) auto-advances to
/// "Minutes Sent settled" (1925:12) after 2.9 s with a 300 ms ease-out.
enum MinutesSentPhase: Equatable {
    case handoff
    case celebrating
    case settled

    var isDone: Bool { self != .handoff }
}

/// Hero artwork: glow, ripples, confetti, success disc with a drawn-on check, and recipient avatars.
/// Geometry comes from the Figma "Celebration" frame (112 pt disc, 48 pt avatars at the four corners).
struct MinutesCelebrationView: View {
    let recipients: [SharedMinutesRecipient]
    let phase: MinutesSentPhase
    let animated: Bool

    private static let avatarOffsets: [CGSize] = [
        CGSize(width: -142, height: -70), CGSize(width: 115, height: -70),
        CGSize(width: -120, height: 92), CGSize(width: 96, height: 92)
    ]

    @State private var appeared = false

    var body: some View {
        ZStack {
            glow
            MinutesConfettiLayer(burst: phase.isDone && animated)
            ForEach(0..<3, id: \.self) { index in
                MinutesRippleView(index: index, active: phase.isDone && animated)
            }
            avatars
            MinutesSuccessDisc(phase: phase, appeared: appeared, animated: animated)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .accessibilityHidden(true)
        .onAppear { appeared = true }
    }

    private var glow: some View {
        Circle()
            .fill(Theme.Colors.manentAccent)
            .frame(width: 210, height: 210)
            .blur(radius: 34)
            .opacity(appeared ? 0.35 : 0)
            .scaleEffect(appeared ? 1 : 0.4)
            .animation(animated ? .easeOut(duration: 0.8) : nil, value: appeared)
    }

    private var avatars: some View {
        let shown = Array(recipients.prefix(Self.avatarOffsets.count).enumerated())
        return ZStack {
            ForEach(shown, id: \.offset) { entry in
                MinutesAvatarBubble(recipient: entry.element,
                                    index: entry.offset,
                                    target: Self.avatarOffsets[entry.offset],
                                    celebrate: phase.isDone,
                                    animated: animated)
            }
        }
    }
}

/// Recipient initials bubble that flies out from the disc, then pops once when the check lands.
struct MinutesAvatarBubble: View {
    let recipient: SharedMinutesRecipient
    let index: Int
    let target: CGSize
    let celebrate: Bool
    let animated: Bool

    @State private var out = false

    var body: some View {
        Text(MeetingRecordInitials.initials(recipient.name))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(Color(hex: recipient.colorHex), in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.10), radius: 6, y: 3)
            .scaleEffect(scale)
            .offset(out ? target : .zero)
            .opacity(out ? 1 : 0)
            .animation(animated ? flyAnimation : nil, value: out)
            .animation(animated ? popAnimation : nil, value: celebrate)
            .onAppear { out = true }
    }

    private var scale: CGFloat {
        if !out { return 0.2 }
        return celebrate ? 1 : 0.88
    }

    private var flyAnimation: Animation {
        .spring(response: 0.55, dampingFraction: 0.7).delay(0.12 + 0.09 * Double(index))
    }

    private var popAnimation: Animation {
        .spring(response: 0.35, dampingFraction: 0.45).delay(0.06 * Double(index))
    }
}

/// 112 pt disc. While handing off it is accent purple with a paper plane and a spinning arc.
/// When Mail or the share sheet reports completion it turns system green and the check draws on.
struct MinutesSuccessDisc: View {
    let phase: MinutesSentPhase
    let appeared: Bool
    let animated: Bool

    @State private var spin = false

    private static let green = Color(red: 0.204, green: 0.78, blue: 0.349)

    var body: some View {
        ZStack {
            Circle()
                .fill(phase.isDone ? Self.green : Theme.Colors.manentAccent)
                .frame(width: 112, height: 112)
                .shadow(color: (phase.isDone ? Self.green : Theme.Colors.manentAccent).opacity(0.35),
                        radius: 14, y: 12)
            spinner
            Image(systemName: "paperplane.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
                .scaleEffect(phase.isDone ? 0.2 : 1)
                .opacity(phase.isDone ? 0 : 1)
            MinutesCheckShape()
                .trim(from: 0, to: phase.isDone ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                .frame(width: 62, height: 48)
                .animation(animated ? .easeOut(duration: 0.45).delay(0.1) : nil, value: phase.isDone)
        }
        .scaleEffect(scale)
        .animation(animated ? .spring(response: 0.5, dampingFraction: 0.62) : nil, value: appeared)
        .animation(animated ? .spring(response: 0.45, dampingFraction: 0.5) : nil, value: phase.isDone)
        .onAppear { spin = true }
    }

    private var scale: CGFloat {
        if !appeared { return 0.4 }
        return phase.isDone ? 1 : 0.92
    }

    private var spinner: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 96, height: 96)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .opacity(phase.isDone || !animated ? 0 : 1)
            .animation(animated ? .linear(duration: 0.9).repeatForever(autoreverses: false) : nil, value: spin)
    }
}

/// Check mark path in a 62 x 48 box, matching the Figma "Checkmark (draws on)" vector.
struct MinutesCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.92))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.98, y: rect.minY + rect.height * 0.04))
        return path
    }
}

/// One expanding ring (Figma "Ripple 1-3": 2 pt accent stroke, 112 pt).
struct MinutesRippleView: View {
    let index: Int
    let active: Bool

    @State private var started = false
    @State private var expanded = false

    var body: some View {
        Circle()
            .strokeBorder(Theme.Colors.manentAccent, lineWidth: 2)
            .frame(width: 112, height: 112)
            .scaleEffect(expanded ? 2.7 : 1)
            .opacity(started && !expanded ? 0.6 : 0)
            .task(id: active) { @MainActor in
                guard active else { return }
                started = true
                withAnimation(.easeOut(duration: 1.3).delay(0.18 * Double(index))) { expanded = true }
            }
    }
}

/// Thirty confetti pieces in the Figma palette. They start hidden behind the disc and burst outward.
struct MinutesConfettiLayer: View {
    let burst: Bool

    @State private var visible = false
    @State private var flying = false
    @State private var faded = false

    private static let palette: [Color] = [
        Color(red: 0.31, green: 0.275, blue: 0.898), Color(red: 0.961, green: 0.62, blue: 0.043),
        Color(red: 1, green: 0.584, blue: 0), Color(red: 1, green: 0.176, blue: 0.333),
        Color(red: 0.204, green: 0.78, blue: 0.349), Color(red: 0.686, green: 0.322, blue: 0.871)
    ]

    private static let pieces: [MinutesConfettiPiece] = (0..<30).map { index in
        let angle = Double(index) * 2.39996323
        let distance = 95.0 + Double((index * 37) % 100)
        return MinutesConfettiPiece(
            id: index,
            target: CGSize(width: cos(angle) * distance, height: sin(angle) * distance + 36),
            width: CGFloat(8 + (index * 5) % 7),
            height: CGFloat(8 + (index * 3) % 7),
            isRound: index % 3 == 0,
            spin: Double((index * 53) % 540) + 120,
            color: palette[index % palette.count]
        )
    }

    var body: some View {
        ZStack {
            ForEach(Self.pieces) { piece in
                MinutesConfettiPieceView(piece: piece, flying: flying)
            }
        }
        .opacity(visible && !faded ? 1 : 0)
        .animation(.easeIn(duration: 0.6), value: faded)
        .task(id: burst) { @MainActor in
            guard burst else { return }
            visible = true
            withAnimation(.easeOut(duration: 1.3)) { flying = true }
            try? await Task.sleep(for: .milliseconds(800))
            faded = true
        }
    }
}

struct MinutesConfettiPiece: Identifiable, Sendable {
    let id: Int
    let target: CGSize
    let width: CGFloat
    let height: CGFloat
    let isRound: Bool
    let spin: Double
    let color: Color
}

struct MinutesConfettiPieceView: View {
    let piece: MinutesConfettiPiece
    let flying: Bool

    var body: some View {
        Group {
            if piece.isRound {
                Circle().fill(piece.color).frame(width: piece.width, height: piece.width)
            } else {
                RoundedRectangle(cornerRadius: 2).fill(piece.color)
                    .frame(width: piece.width + 4, height: piece.height)
            }
        }
        .rotationEffect(.degrees(flying ? piece.spin : 0))
        .offset(flying ? piece.target : .zero)
    }
}
