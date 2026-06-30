import XCTest
@testable import OhhLens

final class FunASRStreamingClientTests: XCTestCase {
    func test_startMessageUsesTextControlPayloadExpectedByBackend() throws {
        let payload = try FunASRStreamingClient.startMessage(
            language: "en",
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
    }

    func test_mapsPartialEventPayload() throws {
        let event = try FunASRStreamingClient.decodeEvent(
            from: #"{"type":"partial","text":"hello world"}"#.data(using: .utf8)!
        )

        XCTAssertEqual(event, .partial("hello world"))
    }
}
