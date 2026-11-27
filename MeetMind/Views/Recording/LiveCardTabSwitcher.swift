import SwiftUI

/// Which list the live card shows: the spoken transcript or the notes and photos captured so far.
enum LiveCardTab: Hashable, CaseIterable {
    case transcript
    case captures

    var title: String {
        switch self {
        case .transcript: return "Transcript"
        case .captures: return "Notes & photos"
        }
    }
}

/// Dark segmented control for the live card. The selection capsule slides between
/// tabs with matchedGeometryEffect; each segment is at least 44 pt tall.
struct LiveCardTabSwitcher: View {
    @Binding var selection: LiveCardTab
    let captureCount: Int

    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LiveCardTab.allCases, id: \.self) { tab in
                segment(for: tab)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func segment(for tab: LiveCardTab) -> some View {
        let isSelected = selection == tab
        return Button {
            guard selection != tab else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                selection = tab
            }
        } label: {
            HStack(spacing: 6) {
                Text(tab.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if tab == .captures && captureCount > 0 {
                    Text("\(captureCount)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.7))
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 18)
                        .background(Color.white.opacity(isSelected ? 0.22 : 0.14), in: Capsule())
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white.opacity(isSelected ? 0.9 : 0.6))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .matchedGeometryEffect(id: "liveCardTabSelection", in: selectionNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab == .captures ? "Notes and photos" : "Transcript")
        .accessibilityValue(tab == .captures && captureCount > 0 ? "\(captureCount) items" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
