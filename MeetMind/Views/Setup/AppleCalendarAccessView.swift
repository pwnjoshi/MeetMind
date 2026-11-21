import SwiftUI

/// "Apple Calendar" screen: the user connects the calendar, then iOS shows its own permission prompt.
/// Push it inside an existing NavigationStack.
@MainActor
public struct AppleCalendarAccessView: View {
    @State private var access: CalendarAccess
    @State private var connected: Bool
    @State private var isRequesting = false
    @State private var showsSettingsHint = false
    private let service: AppleCalendarService

    @Environment(\.openURL) private var openURL

    public init(service: AppleCalendarService = .shared) {
        self.service = service
        self._access = State(initialValue: service.access)
        self._connected = State(initialValue: service.isConnected)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                PrepSectionLabel(text: "Access")
                    .padding(.top, 24)
                PrepCard {
                    Button(action: tapAccess) {
                        HStack {
                            Text("Calendar Access").foregroundStyle(.primary)
                            Spacer()
                            Text(connected ? "Allowed" : access.label)
                                .foregroundStyle(PrepStyle.secondaryText)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequesting)
                }
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(PrepStyle.secondaryText)
                    .padding(.horizontal, 16)
            }
            .padding(.horizontal, 16)
        }
        .background(PrepStyle.background.ignoresSafeArea())
        .navigationTitle("Apple Calendar")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            access = service.access
            connected = service.isConnected
        }
        .alert("Calendar Access Is Off", isPresented: $showsSettingsHint) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Turn on Calendars for Manent in Settings to add meetings to your calendar.")
        }
    }

    private var footer: String {
        if connected {
            return "Meetings you schedule in Manent are added to your Apple Calendar. Events stay on this iPhone and in your own calendar accounts."
        }
        return "Allow access to see your scheduled meetings in Manent and start recording from them."
    }

    private func tapAccess() {
        switch access {
        case .notDetermined:
            isRequesting = true
            Task {
                let result = await service.requestFullAccess()
                access = result
                connected = service.isConnected
                isRequesting = false
            }
        case .denied, .restricted:
            showsSettingsHint = true
        case .writeOnly, .fullAccess:
            if !connected {
                Task {
                    let result = await service.requestFullAccess()
                    access = result
                    connected = service.isConnected
                }
            }
        }
    }
}
