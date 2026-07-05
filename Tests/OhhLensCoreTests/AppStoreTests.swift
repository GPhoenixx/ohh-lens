import XCTest
@testable import OhhLens

final class AppStoreTests: XCTestCase {
    @MainActor
    func test_selectedAccentTheme_defaultsToRed() {
        let store = AppStore()

        XCTAssertEqual(store.selectedAccentTheme, .red)
    }

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
    func test_microphonePCMChunksStreamToBackendWhenListeningStarts() async {
        let captureService = LoopbackCaptureService.testDouble(source: .microphone)
        let streamingClient = StubStreamingClient(
            events: [.ready],
            startMode: .blocked
        )

        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            loopbackCaptureServiceFactory: { _, _ in captureService },
            streamingClientFactory: { streamingClient }
        )

        store.selectedSource = .microphone
        store.startListening()
        captureService.receiveTestPCMChunk(Data([0x01, 0x02, 0x03, 0x04]))

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
            if await streamingClient.sentChunks() == [Data([0x01, 0x02, 0x03, 0x04])] {
                break
            }
            await Task.yield()
        }

        let flushedChunks = await streamingClient.sentChunks()
        XCTAssertEqual(flushedChunks, [Data([0x01, 0x02, 0x03, 0x04])])

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
    func test_liveCaptionAutoScrollTriggerFollowsUpdatesToLatestCaption() {
        XCTAssertFalse(
            LiveCaptionAutoScrollTrigger.shouldScroll(
                from: [],
                to: []
            )
        )
        XCTAssertTrue(
            LiveCaptionAutoScrollTrigger.shouldScroll(
                from: ["The first line"],
                to: ["The first line", "The second line"]
            )
        )
        XCTAssertTrue(
            LiveCaptionAutoScrollTrigger.shouldScroll(
                from: ["The first line", "A partial thought"],
                to: ["The first line", "A partial thought that grew longer"]
            )
        )
        XCTAssertFalse(
            LiveCaptionAutoScrollTrigger.shouldScroll(
                from: ["The first line", "The second line"],
                to: ["The first line", "The second line"]
            )
        )
    }

    @MainActor
    func test_defaultStateStartsOnLiveSubtitlesTab() {
        let store = makePureStateStore()

        XCTAssertEqual(store.selectedSection, .liveSubtitles)
        XCTAssertEqual(AppSection.allCases, [
            .liveSubtitles,
            .conversations,
            .fileTranscriber,
            .savedTranscripts,
            .appSettings,
        ])
        XCTAssertEqual(AppSection.allCases.map(\.rawValue), [
            "liveSubtitles",
            "conversations",
            "fileTranscriber",
            "savedTranscripts",
            "appSettings",
        ])
        XCTAssertEqual(AppSection.allCases.map(\.title), [
            "Live Subtitles",
            "Conversations",
            "File Transcriber",
            "Saved Transcripts",
            "App Settings",
        ])
    }

    @MainActor
    func test_fileTranscriptionStateStartsIdle() {
        let store = makePureStateStore()

        XCTAssertEqual(store.fileTranscription.phase, .idle)
        XCTAssertNil(store.fileTranscription.selectedFileURL)
        XCTAssertEqual(store.fileTranscription.progress, 0)
        XCTAssertNil(store.fileTranscription.currentStep)
        XCTAssertEqual(store.fileTranscription.completedLines, [])
    }

    @MainActor
    func test_historyViewerStartsWithFirstHistoryItemSelectedWhenPreviewLoaded() {
        let store = makePureStateStore()

        store.applyPreviewTranscript()

        XCTAssertEqual(store.historyViewer.selectedSessionID, store.history.first?.id)
        XCTAssertEqual(store.historyViewer.searchText, "")
    }

    @MainActor
    func test_historyViewerStartsWithFirstPersistedHistoryItemSelected() throws {
        let historyStore = HistoryStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let first = SessionRecord(source: .microphone, languages: LanguagePair(source: "en", target: "en"))
        let second = SessionRecord(source: .systemAudio, languages: LanguagePair(source: "en", target: "en"))
        try historyStore.save([first, second])

        let store = AppStore(historyStore: historyStore, deviceCatalog: .init())

        XCTAssertEqual(store.history.map(\.id), [first.id, second.id])
        XCTAssertEqual(store.historyViewer.selectedSessionID, first.id)
    }

    @MainActor
    func test_historyViewerSelectionStaysSynchronizedWithHistoryChanges() {
        let store = makePureStateStore()
        let first = SessionRecord(source: .microphone, languages: store.languagePair)
        let second = SessionRecord(source: .systemAudio, languages: store.languagePair)

        store.history = [first, second]
        store.selectHistorySession(second.id)
        XCTAssertEqual(store.historyViewer.selectedSessionID, second.id)

        store.history = [first]

        XCTAssertEqual(store.historyViewer.selectedSessionID, first.id)
    }

    @MainActor
    func test_historyViewerSearchCanBeUpdated() {
        let store = makePureStateStore()

        store.updateHistorySearch("retro meeting")

        XCTAssertEqual(store.historyViewer.searchText, "retro meeting")
    }

    @MainActor
    func test_liveTranscriptStateExposesConversationRowsFromFinalizedLines() {
        let store = makePureStateStore()

        store.handleStreamingEvent(.final("Speaker A: Hello there"))
        store.handleStreamingEvent(.final("Speaker B: Hi back"))

        XCTAssertEqual(store.conversationRows.count, 2)
        XCTAssertEqual(store.conversationRows[0].speaker, "Speaker A")
        XCTAssertEqual(store.conversationRows[0].text, "Hello there")
        XCTAssertNil(store.conversationRows[0].timestampLabel)
        XCTAssertEqual(store.conversationRows[1].speaker, "Speaker B")
        XCTAssertEqual(store.conversationRows[1].text, "Hi back")
        XCTAssertNil(store.conversationRows[1].timestampLabel)
    }

    @MainActor
    func test_conversationRowsFallbackForMalformedSpeakerPrefixWithoutInventingTimestamp() {
        let store = makePureStateStore()

        store.handleStreamingEvent(.final("Speaker A:"))

        XCTAssertEqual(store.conversationRows.count, 1)
        XCTAssertEqual(store.conversationRows[0].speaker, "Speaker A")
        XCTAssertEqual(store.conversationRows[0].text, "Speaker A:")
        XCTAssertNil(store.conversationRows[0].timestampLabel)
    }

    @MainActor
    func test_conversationRowsUseRealSegmentStartTimeWhenAvailable() {
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
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        store.selectedSource = .systemAudio
        store.selectedLoopbackDeviceID = "blackhole"
        store.startListening()

        let beforeLabel = formatter.string(from: Date())
        store.handleStreamingEvent(.final("Speaker A: Hello there"))
        let afterLabel = formatter.string(from: Date())

        XCTAssertEqual(store.conversationRows.count, 1)
        XCTAssertEqual(store.conversationRows[0].speaker, "Speaker A")
        XCTAssertEqual(store.conversationRows[0].text, "Hello there")
        guard let timestampLabel = store.conversationRows[0].timestampLabel else {
            return XCTFail("Expected a real timestamp label for a live session segment.")
        }
        XCTAssertTrue([beforeLabel, afterLabel].contains(timestampLabel))

        store.stopListening()
    }

    @MainActor
    func test_pipStateCanToggleVisibility() {
        let store = makePureStateStore()

        XCTAssertFalse(store.pipState.isVisible)

        store.togglePiP()
        XCTAssertTrue(store.pipState.isVisible)

        store.togglePiP()
        XCTAssertFalse(store.pipState.isVisible)
    }

    @MainActor
    func test_beginAndCompleteFileTranscriptionAdvanceWorkflowState() {
        let store = makePureStateStore()
        let fileURL = URL(fileURLWithPath: "/tmp/demo.wav")

        store.beginFileTranscription(for: fileURL)

        XCTAssertEqual(store.selectedSection, .fileTranscriber)
        XCTAssertEqual(store.fileTranscription.phase, .processing)
        XCTAssertEqual(store.fileTranscription.selectedFileURL, fileURL)
        XCTAssertEqual(store.fileTranscription.progress, 0)
        XCTAssertEqual(store.fileTranscription.currentStep, "Extracting audio channel")

        store.completeFileTranscription(lines: ["First line", "Second line"])

        XCTAssertEqual(store.fileTranscription.phase, .completed)
        XCTAssertEqual(store.fileTranscription.progress, 1)
        XCTAssertEqual(store.fileTranscription.completedLines, ["First line", "Second line"])
    }

    @MainActor
    func test_updateFileTranscriptionProgressTracksCurrentStepWithoutClearingSelection() {
        let store = makePureStateStore()
        let fileURL = URL(fileURLWithPath: "/tmp/interview.mov")

        store.beginFileTranscription(for: fileURL)
        store.updateFileTranscriptionProgress(step: "Running speech recognition", progress: 0.64)

        XCTAssertEqual(store.fileTranscription.phase, .processing)
        XCTAssertEqual(store.fileTranscription.selectedFileURL, fileURL)
        XCTAssertEqual(store.fileTranscription.currentStep, "Running speech recognition")
        XCTAssertEqual(store.fileTranscription.progress, 0.64, accuracy: 0.000_1)
        XCTAssertEqual(store.fileTranscription.completedLines, [])
    }

    @MainActor
    func test_resetFileTranscriptionReturnsWorkflowToIdleState() {
        let store = makePureStateStore()
        let fileURL = URL(fileURLWithPath: "/tmp/interview.mov")

        store.beginFileTranscription(for: fileURL)
        store.updateFileTranscriptionProgress(step: "Translating transcript", progress: 0.92)
        store.completeFileTranscription(lines: ["Welcome back everyone."])

        store.resetFileTranscription()

        XCTAssertEqual(store.fileTranscription.phase, .idle)
        XCTAssertNil(store.fileTranscription.selectedFileURL)
        XCTAssertEqual(store.fileTranscription.progress, 0)
        XCTAssertNil(store.fileTranscription.currentStep)
        XCTAssertEqual(store.fileTranscription.completedLines, [])
    }

    @MainActor
    func test_defaultStateStartsOnLiveSectionWithDualLineCaptions() {
        let store = makePureStateStore()

        XCTAssertEqual(store.selectedSection, .liveSubtitles)
        XCTAssertEqual(store.captionMode, .dualLine)
        XCTAssertEqual(store.selectedSource, .microphone)
        XCTAssertEqual(store.languagePair.source, "en")
        XCTAssertEqual(store.languagePair.target, "en")
    }

    @MainActor
    func test_startListeningMarksSessionActive() {
        let captureService = LoopbackCaptureService.testDouble(source: .microphone)
        let streamingClient = StubStreamingClient(events: [.ready], startMode: .blocked)
        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            loopbackCaptureServiceFactory: { _, _ in captureService },
            streamingClientFactory: { streamingClient }
        )

        store.selectedSource = .microphone
        store.startListening()

        XCTAssertTrue(store.isListening)
        XCTAssertEqual(store.statusText, "Listening for audio")
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

@MainActor
private func makePureStateStore() -> AppStore {
    AppStore(historyStore: nil, deviceCatalog: .init())
}
