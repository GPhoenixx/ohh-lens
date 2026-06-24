import AVFoundation
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

    public static func systemDefault() -> AudioDeviceCatalog {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        let discoveredDevices = discoverySession.devices.map { device in
            AudioInputDevice(id: device.uniqueID, name: device.localizedName, isInput: true)
        }

        return AudioDeviceCatalog(devices: discoveredDevices)
    }

    public func allInputDevices() -> [AudioInputDevice] {
        devices.filter(\.isInput)
    }

    public func loopbackInputDevices() -> [AudioInputDevice] {
        allInputDevices().filter { device in
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
