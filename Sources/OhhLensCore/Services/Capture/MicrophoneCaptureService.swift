import Foundation

public protocol AudioCaptureServicing {
    var source: AudioSource { get }
    func start() throws
    func stop()
}

public final class MicrophoneCaptureService: AudioCaptureServicing {
    public let source: AudioSource = .microphone

    public init() {}

    public func start() throws {}

    public func stop() {}
}
