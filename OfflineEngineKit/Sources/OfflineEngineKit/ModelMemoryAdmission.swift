import Foundation
import Darwin

struct LocalModelConfiguration: Sendable {
    let contextTokens: UInt32
    let inputTokens: Int32
    let outputTokens: Int
    let batchTokens: UInt32
    let microBatchTokens: UInt32
    let reserveBytes: UInt64
    static let standard = LocalModelConfiguration(contextTokens: 4096, inputTokens: 3072,
        outputTokens: 1024, batchTokens: 512, microBatchTokens: 128, reserveBytes: 750_000_000)
    // Bounded KV cache and compute batches for the accuracy-first 4B trial.
    // Real-meeting quality and long-duration qualification remain outstanding.
    static let compact = LocalModelConfiguration(contextTokens: 2048, inputTokens: 1280,
        outputTokens: 768, batchTokens: 256, microBatchTokens: 64, reserveBytes: 500_000_000)
}

enum ModelMemoryAdmission {
    static let maximumBudget: UInt64 = 3_000_000_000
    // Includes KV cache, compute buffers, and margin. This is deliberately
    // conservative: the measured 4B configuration was killed under pressure.
    static let workingReserve: UInt64 = 750_000_000

    static func check(modelBytes: UInt64, availableBytes: UInt64, reserveBytes: UInt64 = workingReserve) throws {
        let budget = min(maximumBudget, availableBytes)
        let (estimate, overflow) = modelBytes.addingReportingOverflow(reserveBytes)
        guard !overflow, estimate <= budget else {
            throw OfflineError.memoryBudget(requiredEstimate: overflow ? UInt64.max : estimate, budget: budget)
        }
    }

    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : 0
    }

    static func checkCurrentFootprint() throws {
        let bytes = footprint()
        guard bytes > 0 else { throw OfflineError.unavailable("Unable to measure model memory safely. Please retry.") }
        guard bytes < maximumBudget else {
            throw OfflineError.memoryBudget(requiredEstimate: bytes, budget: maximumBudget)
        }
    }
}
