import SwiftUI
import PencilKit

/// Draws a signature with a finger or Pencil. The PNG is stored locally in the MoM sidecar.
struct MoMSignatureCanvas: UIViewRepresentable {
    @Binding var canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

struct MoMSignatureSheet: View {
    let signerName: String
    let initialPlace: String
    let onSign: (Data, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()
    @State private var place: String
    @State private var isEmpty = true
    @State private var message: String?

    init(signerName: String, initialPlace: String, onSign: @escaping (Data, String) -> Void) {
        self.signerName = signerName
        self.initialPlace = initialPlace
        self.onSign = onSign
        _place = State(initialValue: initialPlace)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sign here as \(signerName). The signature stays on this iPhone and is added to the PDF.")
                    .font(.subheadline).foregroundStyle(.secondary)
                MoMSignatureCanvas(canvas: $canvas)
                    .frame(height: 220)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6])).foregroundStyle(.secondary))
                    .accessibilityLabel("Signature drawing area")
                HStack {
                    Button("Clear", role: .destructive) {
                        canvas.drawing = PKDrawing()
                    }
                    Spacer()
                }
                TextField("Place (for example Bengaluru)", text: $place)
                    .textFieldStyle(.roundedBorder)
                Spacer()
            }
            .padding(20)
            .navigationTitle("Sign as Chairperson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign", systemImage: "checkmark") { save() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                }
            }
            .alert("Signature", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    private func save() {
        let drawing = canvas.drawing
        guard !drawing.bounds.isEmpty else {
            message = "Draw your signature first."
            return
        }
        let image = drawing.image(from: drawing.bounds.insetBy(dx: -8, dy: -8), scale: 2)
        guard let png = image.pngData() else {
            message = "The signature could not be saved."
            return
        }
        onSign(png, place)
        dismiss()
    }
}
