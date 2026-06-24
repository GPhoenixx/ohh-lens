import Foundation

public final class LoopbackCaptureService: AudioCaptureServicing {
    public let source: AudioSource

    public init(source: AudioSource) {
        self.source = source
    }

    public func start() throws {}

    public func stop() {}
}
