import AVFoundation
import Foundation

public enum MicrophonePermissionState: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted

    public var isAuthorized: Bool {
        self == .granted
    }
}

public struct PermissionsSnapshot: Equatable, Sendable {
    public var microphonePermission: MicrophonePermissionState

    public init(microphonePermission: MicrophonePermissionState) {
        self.microphonePermission = microphonePermission
    }

    public var microphoneAuthorized: Bool {
        microphonePermission.isAuthorized
    }
}

public protocol PermissionsServicing: Sendable {
    func currentSnapshot() -> PermissionsSnapshot
    func requestMicrophoneAccess() async -> Bool
}

public struct PermissionsService: PermissionsServicing {
    public init() {}

    public func currentSnapshot() -> PermissionsSnapshot {
        PermissionsSnapshot(microphonePermission: Self.map(status: AVCaptureDevice.authorizationStatus(for: .audio)))
    }

    public func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func map(status: AVAuthorizationStatus) -> MicrophonePermissionState {
        switch status {
        case .authorized:
            .granted
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .denied
        }
    }
}
