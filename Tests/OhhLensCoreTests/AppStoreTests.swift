import XCTest
@testable import OhhLensCore

final class AppStoreTests: XCTestCase {
    @MainActor
    func test_defaultStateStartsOnLiveSectionWithDualLineCaptions() {
        let store = AppStore()

        XCTAssertEqual(store.selectedSection, .live)
        XCTAssertEqual(store.captionMode, .dualLine)
        XCTAssertEqual(store.selectedSource, .microphone)
    }

    @MainActor
    func test_startListeningMarksSessionActive() {
        let store = AppStore()

        store.startListening()

        XCTAssertTrue(store.isListening)
        XCTAssertEqual(store.statusText, "Listening")
    }
}
