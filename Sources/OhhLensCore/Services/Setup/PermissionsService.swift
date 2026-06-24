import Foundation

public struct PermissionsSnapshot: Equatable {
    public var microphoneAuthorized: Bool

    public init(microphoneAuthorized: Bool) {
        self.microphoneAuthorized = microphoneAuthorized
    }
}

public struct PermissionsService {
    public init() {}

    public func currentSnapshot() -> PermissionsSnapshot {
        PermissionsSnapshot(microphoneAuthorized: true)
    }
}
