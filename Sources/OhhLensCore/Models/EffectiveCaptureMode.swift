import Foundation

public enum EffectiveCaptureMode: Equatable, Codable {
    case microphone
    case systemAudioLoopback
    case systemAudioRequiresLoopback
    case systemAudioFallbackMicrophone
    case appAudioLoopback
    case appAudioRequiresLoopback
}
