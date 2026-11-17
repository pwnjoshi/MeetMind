import Foundation
import AVFoundation
import Speech
import EventKit
import UserNotifications
import UIKit

/// Production implementation of PermissionsServiceProtocol interfacing with iOS platform frameworks
public final class SystemPermissionsService: PermissionsServiceProtocol, @unchecked Sendable {
    private let eventStore = EKEventStore()
    
    public init() {}
    
    public var settingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }
    
    public func status(for permission: PermissionType) -> PermissionStatus {
        switch permission {
        case .microphone:
            if #available(iOS 17.0, *) {
                switch AVAudioApplication.shared.recordPermission {
                case .granted: return .authorized
                case .denied: return .denied
                case .undetermined: return .notDetermined
                @unknown default: return .notDetermined
                }
            } else {
                switch AVAudioSession.sharedInstance().recordPermission {
                case .granted: return .authorized
                case .denied: return .denied
                case .undetermined: return .notDetermined
                @unknown default: return .notDetermined
                }
            }
            
        case .speechRecognition:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .authorized
            case .denied: return .denied
            case .restricted: return .restricted
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
            
        case .calendar:
            let ekStatus = EKEventStore.authorizationStatus(for: .event)
            switch ekStatus {
            case .fullAccess, .authorized: return .authorized
            case .denied: return .denied
            case .restricted: return .restricted
            case .notDetermined, .writeOnly: return .notDetermined
            @unknown default: return .notDetermined
            }
            
        case .reminders:
            let ekStatus = EKEventStore.authorizationStatus(for: .reminder)
            switch ekStatus {
            case .fullAccess, .authorized: return .authorized
            case .denied: return .denied
            case .restricted: return .restricted
            case .notDetermined, .writeOnly: return .notDetermined
            @unknown default: return .notDetermined
            }
            
        case .notifications:
            // Synchronous lookup placeholder; defaults to notDetermined until async check
            return .notDetermined
        }
    }
    
    public func requestPermission(for permission: PermissionType) async -> PermissionStatus {
        switch permission {
        case .microphone:
            if #available(iOS 17.0, *) {
                let granted = await AVAudioApplication.requestRecordPermission()
                return granted ? .authorized : .denied
            } else {
                return await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        continuation.resume(returning: granted ? .authorized : .denied)
                    }
                }
            }
            
        case .speechRecognition:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { authStatus in
                    switch authStatus {
                    case .authorized: continuation.resume(returning: .authorized)
                    case .denied: continuation.resume(returning: .denied)
                    case .restricted: continuation.resume(returning: .restricted)
                    case .notDetermined: continuation.resume(returning: .notDetermined)
                    @unknown default: continuation.resume(returning: .notDetermined)
                    }
                }
            }
            
        case .calendar:
            do {
                if #available(iOS 17.0, *) {
                    let granted = try await eventStore.requestFullAccessToEvents()
                    return granted ? .authorized : .denied
                } else {
                    return await withCheckedContinuation { continuation in
                        eventStore.requestAccess(to: .event) { granted, _ in
                            continuation.resume(returning: granted ? .authorized : .denied)
                        }
                    }
                }
            } catch {
                return .denied
            }
            
        case .reminders:
            do {
                if #available(iOS 17.0, *) {
                    let granted = try await eventStore.requestFullAccessToReminders()
                    return granted ? .authorized : .denied
                } else {
                    return await withCheckedContinuation { continuation in
                        eventStore.requestAccess(to: .reminder) { granted, _ in
                            continuation.resume(returning: granted ? .authorized : .denied)
                        }
                    }
                }
            } catch {
                return .denied
            }
            
        case .notifications:
            do {
                let center = UNUserNotificationCenter.current()
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                return granted ? .authorized : .denied
            } catch {
                return .denied
            }
        }
    }
    
    public func requestAllPermissions() async -> [PermissionType: PermissionStatus] {
        var results: [PermissionType: PermissionStatus] = [:]
        for type in PermissionType.allCases {
            let status = await requestPermission(for: type)
            results[type] = status
        }
        return results
    }
}
