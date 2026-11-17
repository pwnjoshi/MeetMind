import SwiftUI

/// Microphone check screen matching Figma node 161:1089
public struct MicrophoneCheckView: View {
    @Environment(\.dismiss) private var dismiss
    public let onStartRecording: () -> Void
    
    public init(onStartRecording: @escaping () -> Void) {
        self.onStartRecording = onStartRecording
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "#1C1C1E"))
                    .frame(width: 40, height: 40)
                    .background(Color(hex: "#F0F3FA"))
                    .clipShape(Circle())
            }
            .padding(.top, 8)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Test microphone")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: "#1C1C1E"))
                Text("Speak at a normal volume to check that your iPhone can hear the room.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            
            MicWaveformCardView()
            
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: "#10B981"))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Input detected")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "#1C1C1E"))
                    Text("iPhone microphone (Built-in)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                Spacer()
            }
            .padding(14)
            .background(Color(hex: "#F0F3FA"))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Spacer()
            
            Button(action: {
                dismiss()
                onStartRecording()
            }) {
                Text("Start Recording")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(hex: "#0068D9"))
                    .clipShape(RoundedRectangle(cornerRadius: 26))
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
        .background(Color(uiColor: .systemBackground))
    }
}
