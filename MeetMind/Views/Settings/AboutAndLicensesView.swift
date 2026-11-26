import SwiftUI
import OfflineEngineKit

/// About Manent: version, the privacy statement, and the open-source software and models Manent
/// uses. Full licence texts come from the engine's bundled notices file, which is the single
/// source for attribution (see OfflineEngineKit/Sources/OfflineEngineKit/Resources/notices.txt).
struct AboutAndLicensesView: View {
    private struct Component: Identifiable {
        let name: String
        let role: String
        let license: String
        var id: String { name }
    }

    private static let components: [Component] = [
        Component(name: "WhisperKit (Argmax Open-Source SDK)", role: "Runs speech recognition on this iPhone", license: "MIT"),
        Component(name: "OpenAI Whisper models", role: "Speech recognition models, converted to Core ML by Argmax", license: "MIT"),
        Component(name: "FluidAudio", role: "Speaker separation (diarization)", license: "Apache 2.0"),
        Component(name: "pyannote segmentation 3.0", role: "Speaker segmentation model, converted to Core ML by Fluid Inference", license: "MIT"),
        Component(name: "WeSpeaker ResNet34-LM via pyannote", role: "Speaker voice embedding model, modified Core ML conversion by Fluid Inference", license: "CC BY 4.0"),
        Component(name: "llama.cpp", role: "Runs the language model on this iPhone", license: "MIT"),
        Component(name: "Qwen3.5 2B (GGUF Q4_K_M by Unsloth)", role: "Writes minutes and answers Vidur questions", license: "Apache 2.0"),
    ]

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    private var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Build", value: build)
            }

            Section("Privacy") {
                Text("Recordings, transcripts and minutes stay on this iPhone.")
                    .font(.headline)
                Text("Manent has no account, no analytics and no advertising. Speech recognition, speaker separation and minutes writing run on this iPhone. The only network use is downloading the open models you choose, from huggingface.co. No meeting content is sent in those requests.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(Self.components) { component in
                    VStack(alignment: .leading, spacing: 3) {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(component.name)
                                    .font(.body)
                                    .fixedSize(horizontal: true, vertical: false)
                                Spacer(minLength: 8)
                                Text(component.license)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(component.name).font(.body)
                                Text(component.license).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Text(component.role)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                NavigationLink("Full licence texts") {
                    ScrollView {
                        Text(OfflineModelStore.notices)
                            .font(.footnote)
                            .textSelection(.enabled)
                            .padding()
                    }
                    .navigationTitle("Licences")
                    .navigationBarTitleDisplayMode(.inline)
                }
            } header: {
                Text("Open-source software and models")
            } footer: {
                Text("Models are downloaded unchanged except where noted. Manent does not claim endorsement by the authors listed.")
            }
        }
        .navigationTitle("About and Licences")
        .navigationBarTitleDisplayMode(.inline)
    }
}
