import Foundation

public struct AudioChunkPipeline {
    public init() {}

    public func beginSession(source: AudioSource, languages: LanguagePair) -> SessionRecord {
        SessionRecord(source: source, languages: languages)
    }

    public func appendChunk(
        data: Data,
        transcript: String,
        translation: String?,
        to session: SessionRecord
    ) -> SessionRecord {
        var updated = session
        let now = Date.now.timeIntervalSince1970
        let segment = TranscriptSegment(
            startedAt: now,
            endedAt: now,
            originalText: transcript,
            translatedText: translation
        )
        updated.segments.append(segment)
        return updated
    }
}
