import SwiftUI
import SwiftData

/// Post-recording synthesis HUD container coordinating multi-stage pipeline animation
public struct MeetingProcessingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var processingError: String?
    @State private var viewModel: ProcessingPipelineViewModel
    public let meetingId: UUID
    
    public init(meetingId: UUID, viewModel: ProcessingPipelineViewModel? = nil) {
        self.meetingId = meetingId
        self._viewModel = State(initialValue: viewModel ?? ProcessingPipelineViewModel(meetingId: meetingId))
    }
    
    public init(viewModel: ProcessingPipelineViewModel, meetingId: UUID? = nil) {
        self.meetingId = meetingId ?? UUID()
        self._viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.xs) {
                Text("Synthesizing Minutes")
                    .font(Typography.title2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Analyzing audio, generating summary and action items.")
                    .font(Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Spacing.lg)
            
            ProcessingProgressRingView(progress: viewModel.overallProgress)
            
            Text(viewModel.estimatedRemainingTimeText)
                .font(Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Theme.Colors.cardBackground)
                .clipShape(Capsule())
            
            VStack(spacing: Spacing.sm) {
                ForEach(viewModel.stages) { stage in
                    ProcessingStageRowView(stage: stage) {
                        viewModel.retryCurrentStage()
                    }
                }
            }
            .padding(Spacing.md)
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.cardBorder, lineWidth: 1))
            .padding(.horizontal, Spacing.md)
            
            Spacer()
            if let processingError {
                Text(processingError).foregroundStyle(.red)
                Button("Back to meeting") { dismiss() }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .background(Theme.Colors.background)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.onNavigateToDetail = { id in
                router.navigate(to: .meetingDetail(id: id), in: .home)
            }
        }
        .task {
            do {
                try viewModel.prepareForProduction(context: modelContext)
                try await viewModel.startPipeline()
            } catch {
                processingError = error.localizedDescription
            }
        }
    }
}
