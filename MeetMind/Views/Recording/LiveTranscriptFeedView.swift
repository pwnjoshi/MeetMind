import SwiftUI

/// Live transcript list for the recording card. It follows the newest caption as
/// people speak (throttled to one animated scroll per 0.25 s). Dragging the list
/// down pauses following and shows a "Jump to live" pill; scrolling back to the
/// bottom or tapping the pill resumes it.
struct LiveTranscriptFeedView: View {
    let segments: [LiveTranscriptSegmentItem]
    let bookmarks: [BookmarkItem]
    let interimText: String

    @State private var isFollowing = true
    @State private var isAtBottom = true
    @State private var lastScrollDate = Date.distantPast
    @State private var hasPendingScroll = false
    @State private var flushTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bottomID = "live_transcript_bottom"
    private static let minimumScrollInterval: TimeInterval = 0.25

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if segments.isEmpty && bookmarks.isEmpty && interimText.isEmpty {
                            emptyState
                        }
                        ForEach(segments) { segment in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(segment.speakerName) \u{00B7} \(Self.timecode(segment.startTime))")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                                Text(segment.text)
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                        ForEach(Array(bookmarks.enumerated()), id: \.element.id) { index, mark in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Bookmark \u{00B7} \(Self.timecode(mark.timestamp))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.warmAmber)
                                Text("Bookmark \(index + 1)")
                                    .font(.body)
                                    .foregroundStyle(Theme.Colors.warmAmber)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                        if !interimText.isEmpty {
                            Text(interimText)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomID)
                            .onAppear { isAtBottom = true }
                            .onDisappear { isAtBottom = false }
                    }
                    .padding(.vertical, 2)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8).onChanged { value in
                        // Finger moving down scrolls the content up, away from the live edge.
                        if value.translation.height > 8 && isFollowing {
                            isFollowing = false
                        }
                    }
                    .onEnded { _ in
                        // Content shorter than the card never leaves the live edge.
                        if isAtBottom { isFollowing = true }
                    }
                )

                if !isFollowing {
                    Button {
                        isFollowing = true
                        scrollToBottom(proxy)
                    } label: {
                        Label("Jump to live", systemImage: "arrow.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Color(hex: 0x1B2A6B).opacity(0.92), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.75))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                    .transition(.opacity)
                    .accessibilityHint("Scrolls to the newest caption and keeps following")
                }
            }
            .onChange(of: segments.count) { _, _ in requestScroll(proxy) }
            .onChange(of: segments.last?.text) { _, _ in requestScroll(proxy) }
            .onChange(of: bookmarks.count) { _, _ in requestScroll(proxy) }
            .onChange(of: interimText) { _, _ in requestScroll(proxy) }
            .onChange(of: isAtBottom) { _, atBottom in
                // Scrolling back to the live edge resumes following.
                if atBottom && !isFollowing { isFollowing = true }
            }
            .onChange(of: flushTick) { _, _ in
                if hasPendingScroll {
                    hasPendingScroll = false
                    if isFollowing { scrollToBottom(proxy) }
                }
            }
            .onAppear { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            .task {
                // Flushes a scroll that was throttled so the latest text is never left off screen.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    if hasPendingScroll { flushTick += 1 }
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isFollowing)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
            Text("Listening\u{2026} captions appear as people speak")
                .font(.body)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }

    private func requestScroll(_ proxy: ScrollViewProxy) {
        guard isFollowing else { return }
        if Date().timeIntervalSince(lastScrollDate) >= Self.minimumScrollInterval {
            scrollToBottom(proxy)
        } else {
            hasPendingScroll = true
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        lastScrollDate = Date()
        hasPendingScroll = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
    }

    private static func timecode(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
