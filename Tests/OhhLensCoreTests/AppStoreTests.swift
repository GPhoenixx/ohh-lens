import XCTest
@testable import OhhLens

final class AppStoreTests: XCTestCase {
    @MainActor
    func test_loopbackPCMChunksBufferUntilBackendReady() async {
        let captureService = LoopbackCaptureService.testDouble(source: .systemAudio)
        let streamingClient = StubStreamingClient(
            events: [.ready],
            startMode: .blocked
        )

        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(
                devices: [
                    .init(id: "blackhole", name: "BlackHole 2ch", isInput: true)
                ]
            ),
            loopbackCaptureServiceFactory: { _, _ in captureService },
            streamingClientFactory: { streamingClient }
        )

        store.selectedSource = .systemAudio
        store.selectedLoopbackDeviceID = "blackhole"
        store.startListening()
        captureService.receiveTestPCMChunk(Data([0x10, 0x20, 0x30, 0x40]))

        for _ in 0..<10 {
            if await streamingClient.sentChunks().isEmpty == false {
                break
            }
            await Task.yield()
        }

        let bufferedBeforeReady = await streamingClient.sentChunks()
        XCTAssertEqual(bufferedBeforeReady, [])

        await streamingClient.resumeStartSession()

        for _ in 0..<20 {
            if await streamingClient.sentChunks() == [Data([0x10, 0x20, 0x30, 0x40])] {
                break
            }
            await Task.yield()
        }

        let flushedChunks = await streamingClient.sentChunks()
        XCTAssertEqual(flushedChunks, [Data([0x10, 0x20, 0x30, 0x40])])

        store.stopListening()
    }

    @MainActor
    func test_stopListening_persistsFinalTranscriptToHistory() async {
        let historyStore = HistoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let captureService = LoopbackCaptureService.testDouble(source: .systemAudio)
        let streamingClient = StubStreamingClient(
            events: [.ready, .partial("hel"), .final("hello world"), .closed]
        )

        let store = AppStore(
            historyStore: historyStore,
            deviceCatalog: .init(
                devices: [
                    .init(id: "blackhole", name: "BlackHole 2ch", isInput: true)
                ]
            ),
            loopbackCaptureServiceFactory: { _, _ in captureService },
            streamingClientFactory: { streamingClient }
        )

        store.selectedSource = .systemAudio
        store.selectedLoopbackDeviceID = "blackhole"
        store.startListening()
        captureService.receiveTestPCMChunk(Data([0x00, 0x01]))

        for _ in 0..<10 {
            if store.liveTranscriptState.finalText == "hello world" {
                break
            }
            await Task.yield()
        }

        store.stopListening()

        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(store.history.first?.segments.first?.originalText, "hello world")
    }

    @MainActor
    func test_backendClosedEventStopsListeningAndPersistsCompletedSession() async {
        let historyStore = HistoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let captureService = LoopbackCaptureService.testDouble(source: .systemAudio)
        let streamingClient = StubStreamingClient(
            events: [.ready, .final("closing words"), .closed]
        )

        let store = AppStore(
            historyStore: historyStore,
            deviceCatalog: .init(
                devices: [
                    .init(id: "blackhole", name: "BlackHole 2ch", isInput: true)
                ]
            ),
            loopbackCaptureServiceFactory: { _, _ in captureService },
            streamingClientFactory: { streamingClient }
        )

        store.selectedSource = .systemAudio
        store.selectedLoopbackDeviceID = "blackhole"
        store.startListening()

        for _ in 0..<20 {
            if store.isListening == false {
                break
            }
            await Task.yield()
        }

        XCTAssertFalse(store.isListening)
        XCTAssertEqual(store.backendStatusText, "Backend closed")
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(store.history.first?.segments.first?.originalText, "closing words")
    }

    @MainActor
    func test_liveTranscriptState_defaultsToIdleAndEmptyTranscript() {
        let store = AppStore()

        XCTAssertEqual(store.liveTranscriptState.phase, .idle)
        XCTAssertEqual(store.liveTranscriptState.partialText, "")
        XCTAssertEqual(store.liveTranscriptState.finalText, "")
        XCTAssertEqual(store.liveTranscriptState.visibleCaptionLines, [])
        XCTAssertNil(store.liveTranscriptState.lastError)
    }

    @MainActor
    func test_liveTranscriptStateKeepsTwoLineSubtitleWindow() {
        let store = AppStore()

        store.handleStreamingEvent(.final("The first sentence is ready."))
        store.handleStreamingEvent(.partial("The second sentence is forming"))

        XCTAssertEqual(
            store.liveTranscriptState.visibleCaptionLines,
            [
                "The first sentence is ready.",
                "The second sentence is forming"
            ]
        )

        store.handleStreamingEvent(.final("The second sentence is ready."))
        store.handleStreamingEvent(.partial("The third sentence is forming"))

        XCTAssertEqual(
            store.liveTranscriptState.visibleCaptionLines,
            [
                "The second sentence is ready.",
                "The third sentence is forming"
            ]
        )
    }

    @MainActor
    func test_liveTranscriptStateConcatenatesIncomingPartialFragmentsIntoCurrentLine() {
        let store = AppStore()

        store.handleStreamingEvent(.final("The previous subtitle is stable."))
        store.handleStreamingEvent(.partial("The current"))
        store.handleStreamingEvent(.partial("subtitle is forming"))

        XCTAssertEqual(
            store.liveTranscriptState.visibleCaptionLines,
            [
                "The previous subtitle is stable.",
                "The current subtitle is forming"
            ]
        )

        store.handleStreamingEvent(.final("The current subtitle is complete."))

        XCTAssertEqual(
            store.liveTranscriptState.visibleCaptionLines,
            [
                "The previous subtitle is stable.",
                "The current subtitle is complete."
            ]
        )
        XCTAssertEqual(store.liveTranscriptState.partialText, "")
    }

    @MainActor
    func test_liveTranscriptStateTreatsFullPartialReplacementAsCurrentLine() {
        let store = AppStore()

        store.handleStreamingEvent(.partial("The current"))
        store.handleStreamingEvent(.partial("The current subtitle is forming"))

        XCTAssertEqual(
            store.liveTranscriptState.visibleCaptionLines,
            [
                "The current subtitle is forming"
            ]
        )
    }

    @MainActor
    func test_defaultStateStartsOnLiveSectionWithDualLineCaptions() {
        let store = AppStore()

        XCTAssertEqual(store.selectedSection, .live)
        XCTAssertEqual(store.captionMode, .dualLine)
        XCTAssertEqual(store.selectedSource, .microphone)
        XCTAssertEqual(store.languagePair.source, "en")
        XCTAssertEqual(store.languagePair.target, "en")
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
    func test_selectingSystemAudioUpdatesCaptureLevelWithoutRewritingSessionStatus() {
        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(
                devices: [
                    .init(id: "blackhole", name: "BlackHole 2ch", isInput: true)
                ]
            )
        )

        store.selectedSource = .systemAudio
        store.statusText = "Backend streaming"
        store.updateCaptureLevel(.init(averagePower: -12, peakPower: -6, detectedSound: true))

        XCTAssertTrue(store.captureLevel.detectedSound)
        XCTAssertEqual(store.statusText, "Backend streaming")
    }
}

private actor StubStreamingClient: FunASRStreamingServicing {
    enum StartMode {
        case immediate
        case blocked
    }

    private var events: [FunASRStreamingEvent]
    private let startMode: StartMode
    private var sentAudioChunks: [Data] = []
    private var startContinuation: CheckedContinuation<Void, Never>?

    init(events: [FunASRStreamingEvent], startMode: StartMode = .immediate) {
        self.events = events
        self.startMode = startMode
    }

    func startSession(language: String) async throws {
        if startMode == .blocked {
            await withCheckedContinuation { continuation in
                startContinuation = continuation
            }
        }
    }

    func sendAudioChunk(_ data: Data) async throws {
        sentAudioChunks.append(data)
    }

    func stopSession() async {}

    func nextEvent() async throws -> FunASRStreamingEvent {
        guard events.isEmpty == false else {
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return .closed
        }

        return events.removeFirst()
    }

    func sentChunks() -> [Data] {
        sentAudioChunks
    }

    func resumeStartSession() {
        startContinuation?.resume()
        startContinuation = nil
    }
}
