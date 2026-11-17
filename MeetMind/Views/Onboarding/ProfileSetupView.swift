import SwiftUI

/// Profile setup screen for user identity and personalization
public struct ProfileSetupView: View {
    @Bindable public var viewModel: OnboardingViewModel
    
    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                headerView
                avatarSection
                inputFormSection
                VoiceBaselineCardView(viewModel: viewModel)
                calendarToggleCard
                actionButtons
            }
            .padding(.horizontal, Spacing.lg)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }
    
    private var headerView: some View {
        VStack(spacing: Spacing.xs) {
            Text("Set Up Your Profile")
                .font(Typography.title1)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Personalize your meeting summaries and participant attribution.")
                .font(Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Spacing.lg)
    }
    
    private var avatarSection: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle().fill(Color(hex: viewModel.selectedAvatarColorHex)).frame(width: 88, height: 88)
                Text(viewModel.currentUserProfile.initials).font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
            }
            HStack(spacing: Spacing.sm) {
                ForEach(viewModel.avatarColorPresets, id: \.self) { colorHex in
                    ColorPresetChip(
                        colorHex: colorHex,
                        isSelected: viewModel.selectedAvatarColorHex == colorHex,
                        onSelect: { viewModel.selectedAvatarColorHex = colorHex }
                    )
                }
            }
        }
    }
    
    private var inputFormSection: some View {
        VStack(spacing: Spacing.md) {
            CustomTextField(placeholder: "Full Name (e.g. Sarah Connor)", text: $viewModel.name, icon: "person.fill")
            CustomTextField(placeholder: "Work Role (e.g. Engineering Lead)", text: $viewModel.role, icon: "briefcase.fill")
            CustomTextField(placeholder: "Work Email (optional)", text: $viewModel.email, icon: "envelope.fill")
        }
    }
    
    private var calendarToggleCard: some View {
        Toggle(isOn: $viewModel.isCalendarSyncEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Calendar Integration")
                    .font(Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Automatically link meetings with scheduled calendar events")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .tint(Theme.Colors.primarySlate)
        .padding(Spacing.md)
        .background(Theme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Spacing.Radius.md).stroke(Theme.Colors.cardBorder, lineWidth: 1))
    }
    
    private var actionButtons: some View {
        VStack(spacing: Spacing.sm) {
            PrimaryButton(title: "Save & Continue", icon: "arrow.right", isEnabled: viewModel.canProceedFromProfile) {
                viewModel.saveProfileAndContinue()
            }
            GhostButton(title: "Skip for Now") {
                viewModel.skipProfileSetup()
            }
        }
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.xl)
    }
}
