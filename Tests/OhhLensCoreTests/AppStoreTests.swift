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

    @MainActor
    func test_overlayModeCanSwitchBetweenAllThreeDisplayModes() {
        let store = AppStore()

        store.captionMode = .originalOnly
        XCTAssertEqual(store.captionMode, .originalOnly)

        store.captionMode = .translationOnly
        XCTAssertEqual(store.captionMode, .translationOnly)

        store.captionMode = .dualLine
        XCTAssertEqual(store.captionMode, .dualLine)
    }
}
