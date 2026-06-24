import Foundation
import XCTest
@testable import OhhLensCore

final class HistoryStoreTests: XCTestCase {
    func test_loadReturnsEmptyWhenHistoryFileDoesNotExist() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HistoryStore(baseDirectory: tempDirectory)

        XCTAssertEqual(try store.load(), [])
    }

    func test_saveAndReloadRoundTripsSessionRecords() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HistoryStore(baseDirectory: tempDirectory)
        let session = SessionRecord(
            source: .microphone,
            languages: .init(source: "auto", target: "en"),
            createdAt: Date(timeIntervalSince1970: 1_718_000_000),
            segments: [
                TranscriptSegment(
                    startedAt: 0,
                    endedAt: 2.5,
                    originalText: "Hello there",
                    translatedText: "Xin chao"
                )
            ]
        )

        try store.save([session])
        let reloaded = try store.load()

        XCTAssertEqual(reloaded, [session])
    }

    func test_exportSRTFormatsTimecodesAndIncludesTranslationWhenPresent() {
        let store = HistoryStore(baseDirectory: FileManager.default.temporaryDirectory)
        let session = SessionRecord(
            source: .microphone,
            languages: .init(source: "ja", target: "en"),
            segments: [
                TranscriptSegment(
                    startedAt: 1.25,
                    endedAt: 3.75,
                    originalText: "Konnichiwa",
                    translatedText: "Hello"
                ),
                TranscriptSegment(
                    startedAt: 65,
                    endedAt: 66.2,
                    originalText: "Arigato"
                )
            ]
        )

        XCTAssertEqual(
            store.exportSRT(for: session),
            """
            1
            00:00:01,250 --> 00:00:03,750
            Konnichiwa
            Hello

            2
            00:01:05,000 --> 00:01:06,200
            Arigato
            """
        )
    }
}
