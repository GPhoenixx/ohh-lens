import Foundation

public struct PiPViewState: Equatable, Sendable {
    public var isVisible: Bool
    public var fontSize: Double
    public var opacity: Double

    public init(
        isVisible: Bool = false,
        fontSize: Double = 14,
        opacity: Double = 0.8
    ) {
        self.isVisible = isVisible
        self.fontSize = fontSize
        self.opacity = opacity
    }
}
