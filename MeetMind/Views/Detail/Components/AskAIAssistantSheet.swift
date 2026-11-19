import SwiftUI

/// Conversational Ask AI assistant sheet answering questions grounded in meeting transcripts
public struct AskAIAssistantSheet: View {
    @Environment(\.scenePhase) private var scenePhase
    public let meetingTitle: String
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
        meetingTitle: String = "this meeting",
        isBusy: Bool = false
    ) {
        self.meetingTitle = meetingTitle
        self.history = history
        self.onAsk = onAsk
        self.onSeekToCitation = onSeekToCitation
        self.onDismiss = onDismiss
        self.isBusy = isBusy
    }
    
    public var body: some View {
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
            .background(Color(uiColor: .systemGroupedBackground))
            .tint(Theme.Colors.manentAccent)
            .navigationTitle("Vidur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Vidur").font(.headline)
                        Text(meetingTitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        .onChange(of: scenePhase) { _, phase in if phase != .active { onDismiss() } }
        .onChange(of: isBusy) { _, busy in UIApplication.shared.isIdleTimerDisabled = busy }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title).foregroundStyle(Theme.Colors.manentAccent)
                .frame(width: 68, height: 68)
                .background(Theme.Colors.manentAccent.opacity(0.08), in: Circle())
            Text("Ask About \(meetingTitle)").font(.title3.bold())
            Text("Answers come from this meeting’s transcript.")
                .foregroundStyle(.secondary).font(.subheadline)
            VStack(alignment: .leading, spacing: 8) {
                Text("Suggested Questions").font(.subheadline).foregroundStyle(.secondary)
                    .padding(.leading, 16)
                VStack(spacing: 0) {
                    ForEach(["What did we decide?", "Which actions did we agree on?", "What is still unresolved?"], id: \.self) { question in
                        Button { onAsk(question) } label: {
                            HStack {
                                Text(question)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(16)
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                        if question != "What is still unresolved?" { Divider().padding(.horizontal, 16) }
                    }
                }.background(.background, in: RoundedRectangle(cornerRadius: 22))
            }.padding(.top, 32)
        }.frame(maxWidth: .infinity)
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
            TextField("Ask about this meeting", text: $queryText)
                .textFieldStyle(.plain)
            Button {
                let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { onAsk(trimmed); queryText = "" }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 28)).foregroundStyle(Theme.Colors.manentAccent)
            }
            .disabled(isBusy || queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule()).padding(.horizontal, 16)
    }
}
