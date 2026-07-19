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
            audioCaptureServiceFactory: { _, _ in captureService },
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
        let captureService = TestAudioCaptureService(source: .microphone)
        let streamingClient = StubStreamingClient(
            events: [.ready],
            startMode: .blocked
        )

        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            audioCaptureServiceFactory: { _, _ in captureService },
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
    func test_systemAudioWithoutLoopbackFallsBackToMicrophoneCapture() {
        let captureService = TestAudioCaptureService(source: .microphone)
        var requestedSource: AudioSource?
        var requestedDeviceID: String?

        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            audioCaptureServiceFactory: { source, deviceID in
                requestedSource = source
                requestedDeviceID = deviceID
                return captureService
            },
            streamingClientFactory: { StubStreamingClient(events: [.ready]) }
        )

        store.selectedSource = .systemAudio
        store.selectedLoopbackDeviceID = nil
        defer { store.stopListening() }
        store.startListening()

        XCTAssertEqual(requestedSource, .microphone)
        XCTAssertNil(requestedDeviceID)
        XCTAssertEqual(store.effectiveCaptureMode, .systemAudioFallbackMicrophone)
        XCTAssertEqual(store.statusText, "Listening with Live Audio")
    }

    @MainActor
    func test_appAudioWithoutLoopbackStaysBlocked() {
        var factoryCallCount = 0
        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            audioCaptureServiceFactory: { _, _ in
                factoryCallCount += 1
                return TestAudioCaptureService(source: .appAudio)
            },
            streamingClientFactory: { StubStreamingClient(events: [.ready]) }
        )

        store.selectedSource = .appAudio
        store.selectedLoopbackDeviceID = nil
        store.startListening()

        XCTAssertEqual(factoryCallCount, 0)
        XCTAssertFalse(store.isListening)
        XCTAssertEqual(store.effectiveCaptureMode, .appAudioRequiresLoopback)
        XCTAssertEqual(store.statusText, "App Audio requires loopback")
    }

    @MainActor
    func test_systemAudioFallbackUsesLiveAudioMessaging() {
        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            audioCaptureServiceFactory: { _, _ in TestAudioCaptureService(source: .microphone) },
            streamingClientFactory: { StubStreamingClient(events: [.ready]) }
        )

        store.selectedSource = .systemAudio

        XCTAssertEqual(store.effectiveCaptureMode.statusLabel, "Live Audio")
        XCTAssertEqual(store.liveIdleMessage, "Press Start Listening to capture live audio through your microphone.")
    }

    @MainActor
    func test_systemAudioFallbackCentralizesCopyByCaptureMode() {
        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            audioCaptureServiceFactory: { _, _ in TestAudioCaptureService(source: .microphone) },
            streamingClientFactory: { StubStreamingClient(events: [.ready]) }
        )

        store.selectedSource = .systemAudio

        let copy = store.effectiveCaptureMode.displayCopy

        XCTAssertEqual(copy.statusLabel, "Live Audio")
        XCTAssertEqual(copy.liveIdleMessage, "Press Start Listening to capture live audio through your microphone.")
        XCTAssertEqual(copy.headerPillText(isListening: false), "Live Audio Ready")
        XCTAssertEqual(copy.headerPillText(isListening: true), "Live Audio")
        XCTAssertFalse(copy.showsAnimatedHeaderPill(isListening: false))
        XCTAssertTrue(copy.showsAnimatedHeaderPill(isListening: true))
        XCTAssertEqual(store.liveIdleMessage, copy.liveIdleMessage)
    }

    @MainActor
    func test_appAudioRequiresLoopbackKeepsHeaderPillStatic() {
        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            audioCaptureServiceFactory: { _, _ in TestAudioCaptureService(source: .appAudio) },
            streamingClientFactory: { StubStreamingClient(events: [.ready]) }
        )

        store.selectedSource = .appAudio

        let copy = store.effectiveCaptureMode.displayCopy

        XCTAssertEqual(copy.headerPillText(isListening: false), "App Audio Needs Loopback")
        XCTAssertEqual(copy.headerPillText(isListening: true), "App Audio Needs Loopback")
        XCTAssertFalse(copy.showsAnimatedHeaderPill(isListening: false))
        XCTAssertFalse(copy.showsAnimatedHeaderPill(isListening: true))
    }

    @MainActor
    func test_headerPillPromptsForMicrophonePermissionWhenUndetermined() {
        let permissionsService = TestPermissionsService(snapshot: .init(microphonePermission: .notDetermined))
        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            permissionsService: permissionsService,
            audioCaptureServiceFactory: { _, _ in TestAudioCaptureService(source: .microphone) },
            streamingClientFactory: { StubStreamingClient(events: [.ready]) }
        )

        store.selectedSource = .microphone

        XCTAssertEqual(store.headerPillState?.text, "Allow Microphone")
        XCTAssertEqual(store.headerPillState?.action, .requestPermission)
    }

    @MainActor
    func test_microphoneSourceShowsOnlyPermissionPillInHeader() {
        let permissionsService = TestPermissionsService(snapshot: .init(microphonePermission: .granted))
        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            permissionsService: permissionsService,
            audioCaptureServiceFactory: { _, _ in TestAudioCaptureService(source: .microphone) },
            streamingClientFactory: { StubStreamingClient(events: [.ready]) }
        )

        store.selectedSource = .microphone

        XCTAssertFalse(store.showsHeaderLoopbackPicker)
        XCTAssertEqual(store.headerPillState?.text, "Microphone Ready")
    }

    @MainActor
    func test_audioSourcesShowPermissionPillAndLoopbackPickerInHeader() {
        let permissionsService = TestPermissionsService(snapshot: .init(microphonePermission: .granted))
        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            permissionsService: permissionsService,
            audioCaptureServiceFactory: { _, _ in TestAudioCaptureService(source: .microphone) },
            streamingClientFactory: { StubStreamingClient(events: [.ready]) }
        )

        store.selectedSource = .systemAudio
        XCTAssertTrue(store.showsHeaderLoopbackPicker)
        XCTAssertEqual(store.headerPillState?.text, "Microphone Ready")

        store.selectedSource = .appAudio
        XCTAssertTrue(store.showsHeaderLoopbackPicker)
        XCTAssertEqual(store.headerPillState?.text, "Microphone Ready")
    }

    @MainActor
    func test_tappingDeniedMicrophonePillOpensSettings() async {
        let permissionsService = TestPermissionsService(snapshot: .init(microphonePermission: .denied))
        var openedSettings = false
        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            permissionsService: permissionsService,
            openMicrophoneSettings: { openedSettings = true },
            audioCaptureServiceFactory: { _, _ in TestAudioCaptureService(source: .microphone) },
            streamingClientFactory: { StubStreamingClient(events: [.ready]) }
        )

        store.selectedSource = .microphone
        await store.handleHeaderPillAction()

        XCTAssertTrue(openedSettings)
        XCTAssertEqual(store.headerPillState?.text, "Open Microphone Settings")
        XCTAssertEqual(store.headerPillState?.action, .openSettings)
    }

    @MainActor
    func test_tappingUndeterminedMicrophonePillRequestsAccessAndRefreshesState() async {
        let permissionsService = TestPermissionsService(snapshot: .init(microphonePermission: .notDetermined))
        permissionsService.requestResult = true

        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            permissionsService: permissionsService,
            audioCaptureServiceFactory: { _, _ in TestAudioCaptureService(source: .microphone) },
            streamingClientFactory: { StubStreamingClient(events: [.ready]) }
        )

        store.selectedSource = .microphone
        await store.handleHeaderPillAction()

        XCTAssertEqual(permissionsService.requestCallCount, 1)
        XCTAssertEqual(store.headerPillState?.text, "Microphone Ready")
        XCTAssertEqual(store.headerPillState?.action, AppStore.HeaderPillState.Action.none)
    }

    @MainActor
    func test_startListeningRequestsMicrophonePermissionWhenUndetermined() async {
        let permissionsService = TestPermissionsService(snapshot: .init(microphonePermission: .notDetermined))
        permissionsService.requestResult = true
        let captureService = TestAudioCaptureService(source: .microphone)
        var requestedSource: AudioSource?

        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            permissionsService: permissionsService,
            audioCaptureServiceFactory: { source, _ in
                requestedSource = source
                return captureService
            },
            streamingClientFactory: { StubStreamingClient(events: [.ready]) }
        )

        store.selectedSource = .microphone
        defer { store.stopListening() }
        store.startListening()

        for _ in 0..<20 {
            if permissionsService.requestCallCount == 1, requestedSource == .microphone, store.isListening {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(permissionsService.requestCallCount, 1)
        XCTAssertEqual(requestedSource, .microphone)
        XCTAssertTrue(store.isListening)
        XCTAssertEqual(store.headerPillState?.action, AppStore.HeaderPillState.Action.none)
    }

    @MainActor
    func test_startListeningStopsAndExplainsDeniedMicrophonePermission() {
        let permissionsService = TestPermissionsService(snapshot: .init(microphonePermission: .denied))
        var factoryCallCount = 0

        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            permissionsService: permissionsService,
            audioCaptureServiceFactory: { _, _ in
                factoryCallCount += 1
                return TestAudioCaptureService(source: .microphone)
            },
            streamingClientFactory: { StubStreamingClient(events: [.ready]) }
        )

        store.selectedSource = .microphone
        store.startListening()

        XCTAssertEqual(permissionsService.requestCallCount, 0)
        XCTAssertEqual(factoryCallCount, 0)
        XCTAssertFalse(store.isListening)
        XCTAssertEqual(store.statusText, "Microphone access needed")
    }

    @MainActor
    func test_refreshLoopbackDevicesExplainsFallbackAndAppAudioConstraint() {
        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            audioCaptureServiceFactory: { _, _ in TestAudioCaptureService(source: .microphone) },
            streamingClientFactory: { StubStreamingClient(events: [.ready]) }
        )

        store.refreshLoopbackDevices()

        XCTAssertEqual(
            store.setupMessage,
            "No virtual audio device found. System Audio will use Live Audio fallback; App Audio still requires loopback."
        )
    }

    @MainActor
    func test_fallbackSessionRecordsIntendedSourceAndEffectiveCaptureMode() async {
        let historyStore = HistoryStore(
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let captureService = TestAudioCaptureService(source: .microphone)
        let streamingClient = StubStreamingClient(events: [.ready, .final("hello"), .closed])

        let store = AppStore(
            historyStore: historyStore,
            deviceCatalog: .init(),
            audioCaptureServiceFactory: { _, _ in captureService },
            streamingClientFactory: { streamingClient }
        )

        store.selectedSource = .systemAudio
        store.startListening()

        for _ in 0..<20 where store.history.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(store.history.first?.source, .systemAudio)
        XCTAssertEqual(store.history.first?.effectiveCaptureMode, .systemAudioFallbackMicrophone)
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
            audioCaptureServiceFactory: { _, _ in captureService },
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
            audioCaptureServiceFactory: { _, _ in captureService },
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
    func test_translationUpdatesVietnameseForActiveSegment() {
        let store = AppStore()

        store.handleStreamingEvent(.partialSegment(segmentID: "seg-1", text: "i want to review"))
        store.handleStreamingEvent(
            .translation(
                segmentID: "seg-1",
                translationID: "seg-1-translation-1",
                sourceText: "i want to review",
                translatedText: "toi muon xem lai"
            )
        )

        XCTAssertEqual(store.liveTranscriptState.visibleCaptionLines.last, "i want to review")
        XCTAssertEqual(store.liveTranscriptState.visibleTranslationLine, "toi muon xem lai")
        XCTAssertEqual(
            store.liveTranscriptState.translatedCaptionPairs,
            [
                .init(
                    id: "seg-1-translation-1",
                    segmentID: "seg-1",
                    englishText: "i want to review",
                    vietnameseText: "toi muon xem lai"
                )
            ]
        )
    }

    @MainActor
    func test_translationRowsKeepEachEnglishBlockWithItsVietnameseLine() {
        let store = AppStore()

        store.handleStreamingEvent(.partialSegment(segmentID: "seg-1", text: "first block"))
        store.handleStreamingEvent(
            .translation(
                segmentID: "seg-1",
                translationID: "seg-1-translation-1",
                sourceText: "first block",
                translatedText: "khoi dau tien"
            )
        )
        store.handleStreamingEvent(.partialSegment(segmentID: "seg-1", text: "first block second block"))
        store.handleStreamingEvent(
            .translation(
                segmentID: "seg-1",
                translationID: "seg-1-translation-2",
                sourceText: "second block",
                translatedText: "khoi thu hai"
            )
        )

        XCTAssertEqual(store.liveTranscriptState.translatedCaptionPairs.count, 2)
        XCTAssertNil(store.liveTranscriptState.untranslatedDraftText)
    }

    @MainActor
    func test_newSegmentAppendsDelayedTranslationForThePreviousSegment() {
        let store = AppStore()

        store.handleStreamingEvent(.partialSegment(segmentID: "seg-1", text: "old words"))
        store.handleStreamingEvent(
            .translation(
                segmentID: "seg-1",
                translationID: "seg-1-translation-1",
                sourceText: "old words",
                translatedText: "tu cu"
            )
        )
        store.handleStreamingEvent(.partialSegment(segmentID: "seg-2", text: "new words"))
        store.handleStreamingEvent(
            .translation(
                segmentID: "seg-1",
                translationID: "seg-1-translation-2",
                sourceText: "old words",
                translatedText: "ban dich cu"
            )
        )

        XCTAssertEqual(store.liveTranscriptState.visibleCaptionLines.last, "new words")
        XCTAssertEqual(store.liveTranscriptState.visibleTranslationLine, "ban dich cu")
        XCTAssertEqual(
            store.liveTranscriptState.translatedCaptionPairs.last,
            .init(
                id: "seg-1-translation-2",
                segmentID: "seg-1",
                englishText: "old words",
                vietnameseText: "ban dich cu"
            )
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
    func test_liveStatusBadgeOnlyAnimatesWhileListening() {
        XCTAssertEqual(LiveStatusBadgeState.text(isListening: false), "OFFLINE")
        XCTAssertFalse(LiveStatusBadgeState.isAnimated(isListening: false))
        XCTAssertEqual(LiveStatusBadgeState.text(isListening: true), "LIVE")
        XCTAssertTrue(LiveStatusBadgeState.isAnimated(isListening: true))
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
            audioCaptureServiceFactory: { _, _ in captureService },
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
        XCTAssertEqual(store.languagePair.target, "vi")
    }

    @MainActor
    func test_startListeningMarksSessionActive() {
        let captureService = LoopbackCaptureService.testDouble(source: .microphone)
        let streamingClient = StubStreamingClient(events: [.ready], startMode: .blocked)
        let store = AppStore(
            historyStore: nil,
            deviceCatalog: .init(),
            audioCaptureServiceFactory: { _, _ in captureService },
            streamingClientFactory: { streamingClient }
        )

        store.selectedSource = .microphone
        store.startListening()

        XCTAssertTrue(store.isListening)
        XCTAssertEqual(store.statusText, "Listening with Microphone")
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

private final class TestAudioCaptureService: AudioCaptureServicing, @unchecked Sendable {
    let source: AudioSource
    var currentLevel = AudioLevelSnapshot()
    var onLevelUpdate: (@Sendable (AudioLevelSnapshot) -> Void)?
    var onPCMChunk: (@Sendable (Data) -> Void)?

    init(source: AudioSource) {
        self.source = source
    }

    func start() throws {}

    func stop() {}

    func receiveTestPCMChunk(_ data: Data) {
        onPCMChunk?(data)
    }
}

private final class TestPermissionsService: PermissionsServicing, @unchecked Sendable {
    var snapshot: PermissionsSnapshot
    var requestResult = false
    var requestCallCount = 0

    init(snapshot: PermissionsSnapshot) {
        self.snapshot = snapshot
    }

    func currentSnapshot() -> PermissionsSnapshot {
        snapshot
    }

    func requestMicrophoneAccess() async -> Bool {
        requestCallCount += 1
        snapshot = .init(microphonePermission: requestResult ? .granted : .denied)
        return requestResult
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

    func startSession(language: String, targetLanguage: String) async throws {
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
