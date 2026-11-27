import SwiftUI
import UIKit

/// Permissions primer screen educating users and orchestrating capability authorizations
public struct PermissionsPrimerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable public var viewModel: OnboardingViewModel
    
    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                headerView
                PrivacyGuaranteeCard()
                permissionRowsList
                enterAppButton
            }
            .padding(.horizontal, Spacing.lg)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .onAppear {
            viewModel.refreshPermissions()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.refreshPermissions()
            }
        }
        .alert("Permission Required", isPresented: $viewModel.shouldShowSettingsAlert) {
            Button("Open Settings") { openSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Access was previously declined. Please open iOS Settings to enable access for Manent.")
        }
    }
    
    private var headerView: some View {
        VStack(spacing: Spacing.xs) {
            Text("Permissions & Capabilities")
                .font(Typography.title1)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Manent needs access to on-device capabilities to record, transcribe, and organize meetings.")
                .font(Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Spacing.lg)
    }
    
    private var permissionRowsList: some View {
        VStack(spacing: Spacing.sm) {
            PermissionRowView(
                permission: .microphone, title: "Microphone", description: "Captures high-fidelity meeting audio",
                iconName: "mic.fill", iconColor: Theme.Colors.coralRed,
                status: viewModel.permissionStatus(for: .microphone),
                onRequest: { Task { await viewModel.requestPermission(.microphone) } }, onOpenSettings: openSettings
            )
            PermissionRowView(
                permission: .speechRecognition, title: "Speech Recognition", description: "Converts spoken speech to text in real-time",
                iconName: "waveform.badge.mic", iconColor: Theme.Colors.liveBlue,
                status: viewModel.permissionStatus(for: .speechRecognition),
                onRequest: { Task { await viewModel.requestPermission(.speechRecognition) } }, onOpenSettings: openSettings
            )
            PermissionRowView(
                permission: .calendar, title: "Calendar", description: "Associates meetings with calendar events",
                iconName: "calendar", iconColor: Theme.Colors.warmAmber,
                status: viewModel.permissionStatus(for: .calendar),
                onRequest: { Task { await viewModel.requestPermission(.calendar) } }, onOpenSettings: openSettings
            )
            PermissionRowView(
                permission: .reminders, title: "Reminders", description: "Syncs meeting action items with Apple Reminders",
                iconName: "checklist", iconColor: Theme.Colors.aiPurple,
                status: viewModel.permissionStatus(for: .reminders),
                onRequest: { Task { await viewModel.requestPermission(.reminders) } }, onOpenSettings: openSettings
            )
            PermissionRowView(
                permission: .notifications, title: "Notifications", description: "Lets Manent tell you when private on-device minutes are ready",
                iconName: "bell.badge", iconColor: Theme.Colors.liveBlue,
                status: viewModel.permissionStatus(for: .notifications),
                onRequest: { Task { await viewModel.requestPermission(.notifications) } }, onOpenSettings: openSettings
            )
        }
    }
    
    private var enterAppButton: some View {
        PrimaryButton(title: "Enter Manent", icon: "sparkles") {
            viewModel.completeOnboarding()
        }
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.xl)
    }
    
    private func openSettings() {
        if let url = viewModel.settingsDeepLinkURL {
            UIApplication.shared.open(url)
        } else if let fallback = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(fallback)
        }
    }
}
