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

    @MainActor
    func test_stopListeningReturnsToIdleState() {
        let store = AppStore()
        store.startListening()

        store.stopListening()

        XCTAssertFalse(store.isListening)
        XCTAssertEqual(store.statusText, "Idle")
    }

    @MainActor
    func test_selectingSystemAudioCanExposeDetectedSoundState() {
        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(
                devices: [
                    .init(id: "blackhole", name: "BlackHole 2ch", isInput: true)
                ]
            )
        )

        store.selectedSource = .systemAudio
        store.updateCaptureLevel(.init(averagePower: -12, peakPower: -6, detectedSound: true))

        XCTAssertTrue(store.captureLevel.detectedSound)
        XCTAssertEqual(store.statusText, "Audio detected")
    }
}
