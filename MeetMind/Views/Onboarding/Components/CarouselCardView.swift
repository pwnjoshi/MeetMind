import SwiftUI

/// Slide card display for Onboarding Welcome Carousel
public struct CarouselCardView: View {
    public let slide: OnboardingSlide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var waveformPhase = 0
    @State private var showsMinutesCheck = false

    private let waveformPhases: [[CGFloat]] = [
        [10, 22, 34, 18, 40, 26, 14, 30, 12],
        [18, 34, 20, 38, 22, 36, 26, 16, 24],
        [26, 14, 38, 28, 16, 30, 40, 20, 34]
    ]
    private let barOpacities = [0.35, 0.43, 0.51, 0.59, 0.68, 0.76, 0.84, 0.92, 1.0]
    
    public init(slide: OnboardingSlide) {
        self.slide = slide
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            illustration
                .accessibilityHidden(true)
                .padding(.bottom, 26)
            Text(slide.title)
                .font(.system(size: 29, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(slide.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)
                .padding(.horizontal, 24)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 20)
    }

    private var illustration: some View {
        GeometryReader { geometry in
            let scale = max(0, min(geometry.size.width, geometry.size.height, 380)) / 380
            ZStack {
                Image("OnboardingHalo").resizable().frame(width: 320, height: 320)
                Image("OnboardingRing").resizable().frame(width: 380, height: 380)
                switch slide.id {
                case 0: recordingArtwork
                case 1: minutesArtwork
                default: vidurArtwork
                }
            }
            .frame(width: 380, height: 380)
            .scaleEffect(scale)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .task(id: reduceMotion) {
            waveformPhase = 0
            showsMinutesCheck = reduceMotion
            guard !reduceMotion else { return }
            if slide.id == 1 {
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    showsMinutesCheck = true
                }
                return
            }
            guard slide.id == 0 else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                withAnimation(.easeInOut(duration: 0.32)) {
                    waveformPhase = (waveformPhase + 1) % waveformPhases.count
                }
            }
        }
    }

    private var recordingArtwork: some View {
        ZStack {
                RoundedRectangle(cornerRadius: 32)
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 211.2, height: 147.2)
                    .rotationEffect(.degrees(-6))
                    .offset(x: 20, y: -23)
                RoundedRectangle(cornerRadius: 35.2)
                    .fill(.white)
                    .frame(width: 224, height: 153.6)
                    .shadow(color: .black.opacity(0.1), radius: 17.6, y: 12.8)
                    .offset(y: 11.2)
                HStack(spacing: 9.6) {
                    ForEach(barOpacities.indices, id: \.self) { index in
                        Capsule()
                            .fill(Color(hex: "#4F46E5").opacity(barOpacities[index]))
                            .frame(width: 9.6, height: waveformPhases[waveformPhase][index] * 1.6)
                    }
                }
                .offset(y: 11.2)
                Image("OnboardingMic")
                    .resizable()
                    .frame(width: 70.4, height: 70.4)
                    .overlay {
                        Image(systemName: "mic").font(.system(size: 27)).foregroundStyle(.white)
                    }
                    .scaleEffect(waveformPhase == 1 ? 1.09 : 1)
                    .offset(x: 102.4, y: 78.4)
        }
    }

    private var minutesArtwork: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach([CGFloat(63), 92, 80, 54], id: \.self) { width in
                Capsule()
                    .fill(Color(uiColor: .systemGray4))
                    .frame(width: width, height: width == 63 ? 12 : 8)
            }
        }
        .padding(.top, 34)
        .padding(.leading, 30)
        .frame(width: 151, height: 189, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 33))
        .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
        .overlay(alignment: .bottomTrailing) {
            Image("OnboardingCheck")
                .resizable()
                .frame(width: 50, height: 50)
                .overlay { Image(systemName: "checkmark").foregroundStyle(.white) }
                .scaleEffect(showsMinutesCheck ? 1 : 0.04)
                .offset(x: 16, y: 16)
        }
    }

    private var vidurArtwork: some View {
        VStack(spacing: 14) {
            Text("Was the budget approved?")
                .padding(.horizontal, 17).padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(Theme.Colors.manentAccent, in: Capsule())
                .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .leading, spacing: 10) {
                Label("Vidur", systemImage: "sparkles")
                    .font(.footnote.bold()).foregroundStyle(Theme.Colors.manentAccent)
                Text("Not yet. It’s waiting for the Finance estimate.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 262, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .frame(maxWidth: .infinity, alignment: .leading)
            Label("Stays on this iPhone", systemImage: "doc.text")
                .font(.footnote.weight(.semibold))
                .padding(12)
                .background(.white, in: Capsule())
                .padding(.top, 8)
        }
        .frame(width: 322)
        .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
    }
}
