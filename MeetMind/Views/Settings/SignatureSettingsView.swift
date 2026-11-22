import SwiftUI
import UIKit

/// H2 Signature. Draw with a finger; saved only on this iPhone.
struct SignatureSettingsView: View {
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var savedImage: UIImage?
    @State private var errorMessage: String?
    private let canvasSize = CGSize(width: 320, height: 160)
    private let store = SignatureStore.shared

    var body: some View {
        Form {
            Section {
                signatureCanvas
                    .frame(maxWidth: .infinity)
                    .frame(height: canvasSize.height)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .gesture(drawingGesture)
                    .accessibilityLabel("Signature drawing area")
            } footer: {
                Text("Used to sign off minutes and PDFs. Stored only on this iPhone.")
            }
            if let savedImage, strokes.isEmpty {
                Section("Saved signature") {
                    Image(uiImage: savedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 80)
                        .accessibilityLabel("Saved signature")
                    Button("Remove Signature", role: .destructive) { removeSignature() }
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Signature")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Clear") { strokes = []; current = [] }
                    .disabled(strokes.isEmpty && current.isEmpty)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveSignature() }
                    .disabled(strokes.isEmpty)
            }
        }
        .task { loadSaved() }
    }

    private var signatureCanvas: some View {
        Canvas { context, _ in
            var all = strokes
            if !current.isEmpty { all.append(current) }
            for stroke in all {
                var path = Path()
                guard let first = stroke.first else { continue }
                path.move(to: first)
                for point in stroke.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in current.append(value.location) }
            .onEnded { _ in
                if !current.isEmpty { strokes.append(current) }
                current = []
            }
    }

    private func loadSaved() {
        if let data = store.load() { savedImage = UIImage(data: data) }
    }

    private func saveSignature() {
        let strokesToDraw = strokes
        let size = canvasSize
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { rendererContext in
            let cg = rendererContext.cgContext
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(2.5)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in strokesToDraw {
                guard let first = stroke.first else { continue }
                cg.move(to: first)
                for point in stroke.dropFirst() { cg.addLine(to: point) }
                cg.strokePath()
            }
        }
        guard let png = image.pngData() else {
            errorMessage = "The signature could not be saved."
            return
        }
        do {
            try store.save(pngData: png)
            savedImage = image
            strokes = []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeSignature() {
        do {
            try store.remove()
            savedImage = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
