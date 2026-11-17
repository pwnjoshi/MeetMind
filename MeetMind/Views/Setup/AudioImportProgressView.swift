import SwiftUI

/// Progress indicator view during audio transcription and processing
public struct AudioImportProgressView: View {
    public let message: String
    
    public init(message: String = "Transcribing audio...") {
        self.message = message
    }
    
    public var body: some View {
        ProgressView(message)
            .tint(Theme.Colors.liveBlue)
            .padding()
    }
}
