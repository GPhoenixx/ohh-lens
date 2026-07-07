import Foundation

public protocol AudioCaptureServicing {
    var source: AudioSource { get }
    var currentLevel: AudioLevelSnapshot { get }
    var onLevelUpdate: (@Sendable (AudioLevelSnapshot) -> Void)? { get set }
    var onPCMChunk: (@Sendable (Data) -> Void)? { get set }
    func start() throws
    func stop()
}
