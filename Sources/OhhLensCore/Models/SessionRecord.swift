import Foundation

public struct SessionRecord: Equatable, Codable, Identifiable {
    public let id: UUID
    public var source: AudioSource
    public var languages: LanguagePair
    public var createdAt: Date
    public var segments: [TranscriptSegment]

    public init(
        id: UUID = UUID(),
        source: AudioSource,
        languages: LanguagePair,
        createdAt: Date = .now,
        segments: [TranscriptSegment] = []
    ) {
        self.id = id
        self.source = source
        self.languages = languages
        self.createdAt = createdAt
        self.segments = segments
    }
}
