import Foundation

public struct TranscriptSegment: Equatable, Codable, Identifiable {
    public let id: UUID
    public let startedAt: TimeInterval
    public let endedAt: TimeInterval
    public let originalText: String
    public let translatedText: String?

    public init(
        id: UUID = UUID(),
        startedAt: TimeInterval,
        endedAt: TimeInterval,
        originalText: String,
        translatedText: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.originalText = originalText
        self.translatedText = translatedText
    }
}
