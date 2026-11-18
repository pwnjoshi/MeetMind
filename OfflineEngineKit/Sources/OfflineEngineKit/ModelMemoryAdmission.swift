import Foundation

enum ModelMemoryAdmission {
    static let maximumBudget: UInt64 = 3_000_000_000
    // Includes KV cache, compute buffers, and margin. This is deliberately
    // conservative: the measured 4B configuration was killed under pressure.
    static let workingReserve: UInt64 = 750_000_000

    static func check(modelBytes: UInt64, availableBytes: UInt64) throws {
        let budget = min(maximumBudget, availableBytes)
        let (estimate, overflow) = modelBytes.addingReportingOverflow(workingReserve)
        guard !overflow, estimate <= budget else {
            throw OfflineError.memoryBudget(requiredEstimate: overflow ? UInt64.max : estimate, budget: budget)
        }
    }
}
