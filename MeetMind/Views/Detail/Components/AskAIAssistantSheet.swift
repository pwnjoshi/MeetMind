import SwiftUI

/// Conversational Ask AI assistant sheet answering questions grounded in meeting transcripts
public struct AskAIAssistantSheet: View {
    @Environment(\.scenePhase) private var scenePhase
    public let history: [(prompt: String, response: AIAnswerResponse)]
    public let onAsk: (String) -> Void
    public let onSeekToCitation: (AICitation) -> Void
    public let onDismiss: () -> Void
    public let isBusy: Bool
    
    @State private var queryText: String = ""
    
    public init(
        history: [(prompt: String, response: AIAnswerResponse)],
        onAsk: @escaping (String) -> Void,
        onSeekToCitation: @escaping (AICitation) -> Void,
        onDismiss: @escaping () -> Void,
        isBusy: Bool = false
    ) {
        self.history = history
        self.onAsk = onAsk
        self.onSeekToCitation = onSeekToCitation
        self.onDismiss = onDismiss
        self.isBusy = isBusy
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.sm) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.md) {
                        if history.isEmpty { emptyStateView }
                        ForEach(0..<history.count, id: \.self) { idx in
                            chatPairView(history[idx])
                        }
                    }
                    .padding(Spacing.lg)
                }
                inputBar
                if isBusy { ProgressView("Reading the transcript on this iPhone…").font(.footnote) }
            }
            .navigationTitle("Ask AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", action: onDismiss) }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { onDismiss() } }
        .onChange(of: isBusy) { _, busy in UIApplication.shared.isIdleTimerDisabled = busy }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "sparkles").font(.system(size: 32)).foregroundStyle(Theme.Colors.aiPurple)
            Text("Ask questions about this meeting").font(Typography.headline)
            Text("AI synthesizes answers grounded in spoken dialogue.").font(Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    private func chatPairView(_ pair: (prompt: String, response: AIAnswerResponse)) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(pair.prompt).font(Typography.headline).foregroundStyle(Theme.Colors.primarySlate)
                .padding(Spacing.sm).background(Theme.Colors.secondaryBackground).clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md))
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(pair.response.answer).font(Typography.body).foregroundStyle(Theme.Colors.textPrimary)
                ForEach(pair.response.citations) { cit in
                    Button { onSeekToCitation(cit) } label: {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "play.circle.fill")
                            Text("[\(cit.formattedTimecode)] \(cit.snippet)")
                        }
                        .font(Typography.caption).foregroundStyle(Theme.Colors.liveBlue)
                    }
                }
            }
            .padding(Spacing.sm).background(Theme.Colors.aiPurpleLight.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md))
        }
    }
    
    private var inputBar: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Ask anything...", text: $queryText)
                .textFieldStyle(.roundedBorder)
            Button {
                let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { onAsk(trimmed); queryText = "" }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 28)).foregroundStyle(Theme.Colors.aiPurple)
            }
            .disabled(isBusy || queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(Spacing.md)
    }
}
