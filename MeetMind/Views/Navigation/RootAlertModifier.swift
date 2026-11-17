import SwiftUI

/// View modifier handling global alerts for RootView
public struct RootAlertModifier: ViewModifier {
    @Bindable public var appState: AppState
    
    public func body(content: Content) -> some View {
        content
            .alert(item: $appState.activeAlert) { alert in
                switch alert {
                case .permissionDenied(let permission, let message):
                    return Alert(
                        title: Text("\(permission) Permission Required"),
                        message: Text(message),
                        primaryButton: .default(Text("Open Settings"), action: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }),
                        secondaryButton: .cancel()
                    )
                case .genericError(let title, let message):
                    return Alert(title: Text(title), message: Text(message), dismissButton: .default(Text("OK")))
                case .confirmDiscardRecording:
                    return Alert(
                        title: Text("Discard Recording?"),
                        message: Text("Recorded audio and interim transcripts will be deleted."),
                        primaryButton: .destructive(Text("Discard")),
                        secondaryButton: .cancel()
                    )
                }
            }
    }
}
