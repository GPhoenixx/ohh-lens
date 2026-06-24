import Foundation

public struct VirtualDeviceStatus: Equatable {
    public enum State: Equatable {
        case ready
        case needsAttention
    }

    public var state: State
    public var message: String

    public init(state: State, message: String) {
        self.state = state
        self.message = message
    }
}

public struct VirtualDeviceDiagnostics {
    public let availableDeviceNames: [String]

    public init(availableDeviceNames: [String]) {
        self.availableDeviceNames = availableDeviceNames
    }

    public func currentStatus() -> VirtualDeviceStatus {
        guard availableDeviceNames.isEmpty == false else {
            return VirtualDeviceStatus(
                state: .needsAttention,
                message: "No virtual audio device found. Install and route system audio through the helper device."
            )
        }

        return VirtualDeviceStatus(
            state: .ready,
            message: "Virtual audio device detected."
        )
    }
}
