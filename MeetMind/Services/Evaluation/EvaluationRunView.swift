import SwiftUI
import UIKit

/// USB-triggered golden-set evaluation (`--offline-evaluation`). It analyses recordings pushed to
/// Documents/Evaluation/<id>/ and writes result.json beside each one. It uses no SwiftData store and
/// never reads or changes a user's meetings. Run it with Scripts/device_eval.py.
@MainActor
struct EvaluationRunView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = "Evaluation run"
    @State private var operation: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            Text("Evaluation run").font(.title2)
            Text(status)
            Text("Keep MeetMind open and the screen on. This analyses only the recordings pushed for evaluation and does not change your saved meetings.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { start() }
        .onDisappear { operation?.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { operation?.cancel() }
        }
    }

    private func start() {
        guard operation == nil else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        let options = EvaluationRunner.options(from: ProcessInfo.processInfo.arguments)
        operation = Task { @MainActor in
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            let passed = await EvaluationRunner.runAll(options: options) { text in status = text }
            status = passed ? "Finished. Results are in Documents/Evaluation." : "Finished with problems. See the console output."
        }
    }
}
