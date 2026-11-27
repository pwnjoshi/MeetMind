import Foundation

/// Where a loaded model runs its work.
public enum ComputePlacement: String, Sendable {
    /// Metal. iOS rejects GPU command buffers from an iPhone app in the background.
    case gpu
    /// CPU (and the Neural Engine through Core ML). Allowed in the background.
    case cpu
    /// A session that does not depend on the GPU state, such as a test double.
    case independent
}

/// Process-wide record of whether GPU work is currently allowed.
///
/// On iPhone, iOS denies Metal command buffers once the app is in the background,
/// including during a continued-processing task. The app updates this flag on
/// foreground and background transitions; model loads read it to choose GPU or CPU.
public enum ComputeEnvironment {
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = true
        func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ newValue: Bool) { lock.lock(); value = newValue; lock.unlock() }
    }

    private static let flag = Flag()

    /// True while the app is in the foreground (or on platforms without the restriction).
    public static var gpuAvailable: Bool { flag.get() }

    public static func setGPUAvailable(_ available: Bool) { flag.set(available) }

    /// The placement a new language model session should use right now.
    static var preferredPlacement: ComputePlacement {
        #if targetEnvironment(simulator)
        return .cpu
        #else
        return gpuAvailable ? .gpu : .cpu
        #endif
    }

    /// Whether a session with `placement` should be replaced to match the current state:
    /// a GPU session cannot run in the background, and a CPU session is slower than
    /// necessary once the app is back in the foreground.
    static func needsReload(_ placement: ComputePlacement) -> Bool {
        switch placement {
        case .independent: return false
        case .gpu, .cpu: return placement != preferredPlacement
        }
    }
}
