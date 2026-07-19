import XCTest
@testable import OhhLens

final class FunASRStreamingClientTests: XCTestCase {
    func test_startMessageUsesTextControlPayloadExpectedByBackend() throws {
        let payload = try FunASRStreamingClient.startMessage(
            language: "en",
            targetLanguage: "vi",
            sessionID: "session-1"
        )
        let data = try XCTUnwrap(payload.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["type"] as? String, "start")
        XCTAssertEqual(json?["session_id"] as? String, "session-1")
        XCTAssertEqual(json?["sample_rate"] as? Int, 16_000)
        XCTAssertEqual(json?["channels"] as? Int, 1)
        XCTAssertEqual(json?["sample_format"] as? String, "pcm_s16le")
        XCTAssertEqual(json?["language"] as? String, "en")
        XCTAssertEqual(json?["target_language"] as? String, "vi")
    }

    func test_mapsPartialEventPayload() throws {
        let event = try FunASRStreamingClient.decodeEvent(
            from: #"{"type":"partial","text":"hello world"}"#.data(using: .utf8)!
        )

        XCTAssertEqual(event, .partial("hello world"))
    }

    func test_startMessagePreservesMultilingualSourceAndTargetCodes() throws {
        let payload = try FunASRStreamingClient.startMessage(
            language: "ja",
            targetLanguage: "ar",
            sessionID: "multilingual-session"
        )
        let data = try XCTUnwrap(payload.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["language"] as? String, "ja")
        XCTAssertEqual(json?["target_language"] as? String, "ar")
    }

    func test_mapsPartialEventPayloadWithSegmentID() throws {
        let event = try FunASRStreamingClient.decodeEvent(
            from: #"{"type":"partial","segment_id":"seg-1","text":"hello world"}"#.data(using: .utf8)!
        )

        XCTAssertEqual(event, .partialSegment(segmentID: "seg-1", text: "hello world"))
    }

    func test_mapsTranslationEventPayload() throws {
        let event = try FunASRStreamingClient.decodeEvent(
            from: #"{"type":"translation","segment_id":"seg-1","translation_id":"seg-1-translation-1","source_text":"hello world","translated_text":"xin chao the gioi"}"#.data(using: .utf8)!
        )

        XCTAssertEqual(
            event,
            .translation(
                segmentID: "seg-1",
                translationID: "seg-1-translation-1",
                sourceText: "hello world",
                translatedText: "xin chao the gioi"
            )
        )
    }
}
