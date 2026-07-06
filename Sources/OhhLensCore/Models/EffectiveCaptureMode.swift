import Foundation

public enum EffectiveCaptureMode: String, Codable, Equatable {
    case microphone
    case routedSystemAudio
    case systemAudioFallbackMicrophone
    case appAudio
    case appAudioRequiresLoopback

    public var statusLabel: String {
        switch self {
        case .microphone:
            "Microphone"
        case .routedSystemAudio:
            "Loopback Device"
        case .systemAudioFallbackMicrophone:
            "Live Audio"
        case .appAudio:
            "App Audio"
        case .appAudioRequiresLoopback:
            "App Audio Unavailable"
        }
    }
}
