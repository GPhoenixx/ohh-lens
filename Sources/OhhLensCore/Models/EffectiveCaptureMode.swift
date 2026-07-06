import Foundation

public enum EffectiveCaptureMode: String, Codable, Equatable {
    public struct DisplayCopy: Equatable {
        public let statusLabel: String
        public let liveIdleMessage: String
        public let showsLoopbackDevicePicker: Bool
        private let readyHeaderPillText: String?
        private let activeHeaderPillText: String?

        init(
            statusLabel: String,
            liveIdleMessage: String,
            showsLoopbackDevicePicker: Bool,
            readyHeaderPillText: String? = nil,
            activeHeaderPillText: String? = nil
        ) {
            self.statusLabel = statusLabel
            self.liveIdleMessage = liveIdleMessage
            self.showsLoopbackDevicePicker = showsLoopbackDevicePicker
            self.readyHeaderPillText = readyHeaderPillText
            self.activeHeaderPillText = activeHeaderPillText
        }

        public func headerPillText(isListening: Bool) -> String? {
            isListening ? activeHeaderPillText : readyHeaderPillText
        }
    }

    case microphone
    case routedSystemAudio
    case systemAudioFallbackMicrophone
    case appAudio
    case appAudioRequiresLoopback

    public var displayCopy: DisplayCopy {
        switch self {
        case .microphone:
            DisplayCopy(
                statusLabel: "Microphone",
                liveIdleMessage: "Press Start Listening to capture live speech from your microphone.",
                showsLoopbackDevicePicker: false,
                readyHeaderPillText: "Microphone Ready",
                activeHeaderPillText: "Microphone Live"
            )
        case .routedSystemAudio:
            DisplayCopy(
                statusLabel: "Loopback Device",
                liveIdleMessage: "Press Start Listening to capture routed system audio in real time.",
                showsLoopbackDevicePicker: true
            )
        case .systemAudioFallbackMicrophone:
            DisplayCopy(
                statusLabel: "Live Audio",
                liveIdleMessage: "Press Start Listening to capture live audio through your microphone.",
                showsLoopbackDevicePicker: false,
                readyHeaderPillText: "Live Audio Ready",
                activeHeaderPillText: "Live Audio"
            )
        case .appAudio:
            DisplayCopy(
                statusLabel: "App Audio",
                liveIdleMessage: "Press Start Listening to capture routed audio from the selected app.",
                showsLoopbackDevicePicker: true
            )
        case .appAudioRequiresLoopback:
            DisplayCopy(
                statusLabel: "App Audio Unavailable",
                liveIdleMessage: "Install a virtual audio device before starting App Audio capture.",
                showsLoopbackDevicePicker: false,
                readyHeaderPillText: "App Audio Needs Loopback",
                activeHeaderPillText: "App Audio Needs Loopback"
            )
        }
    }

    public var statusLabel: String {
        displayCopy.statusLabel
    }
}
