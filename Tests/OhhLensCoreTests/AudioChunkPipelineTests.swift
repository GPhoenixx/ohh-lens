import XCTest
@testable import OhhLensCore

final class AudioChunkPipelineTests: XCTestCase {
    func test_appendChunkAddsTimestampedSegmentPlaceholder() {
        let pipeline = AudioChunkPipeline()
        let session = pipeline.beginSession(
            source: .microphone,
            languages: .init(source: "auto", target: "vi")
        )

        let updated = pipeline.appendChunk(
            data: Data([0x00, 0x01]),
            transcript: "hello",
            translation: "xin chao",
            to: session
        )

        XCTAssertEqual(updated.segments.count, 1)
        XCTAssertEqual(updated.segments.first?.translatedText, "xin chao")
        XCTAssertEqual(updated.source, .microphone)
    }
}
