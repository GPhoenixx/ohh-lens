import Foundation

public struct AudioLevelSnapshot: Equatable, Sendable {
    public var averagePower: Float
    public var peakPower: Float
    public var detectedSound: Bool

    public init(
        averagePower: Float = -160,
        peakPower: Float = -160,
        detectedSound: Bool = false
    ) {
        self.averagePower = averagePower
        self.peakPower = peakPower
        self.detectedSound = detectedSound
    }
}
