// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OfflineEngineKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "OfflineEngineKit", targets: ["OfflineEngineKit"])],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", revision: "9f99b5cb6a907730543823ad271b82532782a899"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "16780f04d2ece24f67d0fc00efccd0296491c1a8", traits: ["Diarizer"]),
    ],
    targets: [
        .binaryTarget(name: "llama", url: "https://github.com/ggml-org/llama.cpp/releases/download/b12491/llama-b12491-xcframework.zip", checksum: "fa1be672f30bc5bb5cd887c734324b8d1538a13cf380bb197f78c1c06ba15011"),
        .target(name: "OfflineEngineKit", dependencies: [
            .product(name: "WhisperKit", package: "argmax-oss-swift"),
            .product(name: "FluidAudio", package: "FluidAudio"), "llama"
        ], resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "OfflineEngineKitTests", dependencies: ["OfflineEngineKit"]),
    ]
)
