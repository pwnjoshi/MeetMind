import AVFoundation
import Foundation

public struct CanonicalRecordingInfo: Sendable, Equatable {
    public let frameCount: Int64
    public let duration: TimeInterval

    public init(frameCount: Int64, duration: TimeInterval) {
        self.frameCount = frameCount
        self.duration = duration
    }
}

public enum CanonicalRecordingValidationError: LocalizedError, Sendable, Equatable {
    case fileMissing
    case unreadableAudio
    case emptyAudio
    case invalidDuration

    public var errorDescription: String? {
        switch self {
        case .fileMissing:
            return "The recording stopped, but the audio file is missing. The meeting was not marked as saved."
        case .unreadableAudio:
            return "The recording stopped, but the audio file could not be opened. The file was preserved for recovery."
        case .emptyAudio:
            return "The recording stopped, but the audio file contains no frames. The file was preserved for recovery."
        case .invalidDuration:
            return "The recording stopped, but its audio duration is invalid. The file was preserved for recovery."
        }
    }
}

public enum CanonicalRecordingValidator {
    public static func validate(
        _ url: URL,
        fileManager: FileManager = .default
    ) throws -> CanonicalRecordingInfo {
        guard fileManager.fileExists(atPath: url.path) else {
            throw CanonicalRecordingValidationError.fileMissing
        }
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw CanonicalRecordingValidationError.unreadableAudio
        }
        let frameCount = Int64(file.length)
        guard frameCount > 0 else {
            throw CanonicalRecordingValidationError.emptyAudio
        }
        let sampleRate = file.processingFormat.sampleRate
        let duration = Double(frameCount) / sampleRate
        guard sampleRate > 0, duration.isFinite, duration > 0 else {
            throw CanonicalRecordingValidationError.invalidDuration
        }
        return CanonicalRecordingInfo(frameCount: frameCount, duration: duration)
    }
}
