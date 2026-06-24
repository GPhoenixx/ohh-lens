import Foundation

public struct AudioInputDevice: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isInput: Bool

    public init(id: String, name: String, isInput: Bool) {
        self.id = id
        self.name = name
        self.isInput = isInput
    }
}

public struct AudioDeviceCatalog {
    private let devices: [AudioInputDevice]

    public init(devices: [AudioInputDevice] = []) {
        self.devices = devices
    }

    public func loopbackInputDevices() -> [AudioInputDevice] {
        devices.filter { device in
            guard device.isInput else {
                return false
            }

            let lowercasedName = device.name.lowercased()
            return lowercasedName.contains("blackhole")
                || lowercasedName.contains("vb-cable")
                || lowercasedName.contains("loopback")
                || lowercasedName.contains("soundflower")
        }
    }
}
