import Foundation
import Observation

@MainActor
@Observable
public final class AppStore {
    private static let appearanceModeDefaultsKey = "selectedAppearanceMode"

    public var selectedSection: AppSection = .liveSubtitles
    public var selectedAccentTheme: AccentTheme = .red
    public var selectedAppearanceMode: AppearanceMode = .system {
        didSet {
            UserDefaults.standard.set(selectedAppearanceMode.rawValue, forKey: Self.appearanceModeDefaultsKey)
        }
    }
    public var selectedSource: AudioSource = .microphone
    public var captionMode: CaptionMode = .dualLine
    public var languagePair = LanguagePair(source: "en", target: "en")
    public var availableLoopbackDevices: [AudioInputDevice] = []
    public var selectedLoopbackDeviceID: String?
    public var captureLevel = AudioLevelSnapshot()
    public var liveTranscriptState = LiveTranscriptState()
    public var isListening = false
    public var statusText = "Idle"
    public var backendStatusText = "Backend idle"
    public var setupMessage = "Checking setup..."
    public var fileTranscription = FileTranscriptionViewState()
    public var historyViewer = HistoryViewerState()
    public var pipState = PiPViewState()
    public var history: [SessionRecord] = [] {
        didSet {
            persistHistory()
            synchronizeHistoryViewerSelection()
        }
    }
    public var effectiveCaptureMode: EffectiveCaptureMode {
        if isListening, let activeCaptureMode {
            return activeCaptureMode
        }

        switch selectedSource {
        case .microphone:
            return .microphone
        case .systemAudio:
            return selectedLoopbackDeviceID == nil ? .systemAudioFallbackMicrophone : .routedSystemAudio
        case .appAudio:
            return selectedLoopbackDeviceID == nil ? .appAudioRequiresLoopback : .appAudio
        case .importedFile:
            return .microphone
        }
    }

    private let historyStore: HistoryStore?
    private let fileTranscriptionService = FileTranscriptionService()
    private let audioChunkPipeline = AudioChunkPipeline()
    private let deviceCatalog: AudioDeviceCatalog
    private let audioCaptureServiceFactory: (AudioSource, String?) -> any AudioCaptureServicing
    private let streamingClientFactory: () -> any FunASRStreamingServicing
    private let streamingChunkSender = StreamingChunkSender()
    private var audioCaptureService: (any AudioCaptureServicing)?
    private var streamingTask: Task<Void, Never>?
    private var streamingClient: (any FunASRStreamingServicing)?
    private var activeCaptureMode: EffectiveCaptureMode?
    private var currentSession: SessionRecord?

    public init() {
        self.historyStore = AppStore.makeDefaultHistoryStore()
        self.deviceCatalog = AppStore.makeDefaultDeviceCatalog()
        self.audioCaptureServiceFactory = { source, deviceID in
            if source == .microphone {
                return MicrophoneCaptureService(deviceID: deviceID)
            }

            return LoopbackCaptureService(source: source, deviceID: deviceID)
        }
        self.streamingClientFactory = { FunASRStreamingClient() }
        self.setupMessage = AppStore.defaultSetupMessage()
        self.selectedAppearanceMode = AppStore.loadAppearanceMode()

        if let historyStore {
            self.history = (try? historyStore.load()) ?? []
        } else {
            self.history = []
        }

        synchronizeHistoryViewerSelection()
        refreshLoopbackDevices()
    }

    public init(
        historyStore: HistoryStore?,
        deviceCatalog: AudioDeviceCatalog = .init(),
        audioCaptureServiceFactory: @escaping (AudioSource, String?) -> any AudioCaptureServicing = { source, deviceID in
            if source == .microphone {
                return MicrophoneCaptureService(deviceID: deviceID)
            }

            return LoopbackCaptureService(source: source, deviceID: deviceID)
        },
        streamingClientFactory: @escaping () -> any FunASRStreamingServicing = { FunASRStreamingClient() }
    ) {
        self.historyStore = historyStore
        self.deviceCatalog = deviceCatalog
        self.audioCaptureServiceFactory = audioCaptureServiceFactory
        self.streamingClientFactory = streamingClientFactory
        self.setupMessage = AppStore.defaultSetupMessage()
        self.selectedAppearanceMode = AppStore.loadAppearanceMode()

        if let historyStore {
            self.history = (try? historyStore.load()) ?? []
        } else {
            self.history = []
        }

        synchronizeHistoryViewerSelection()
        refreshLoopbackDevices()
    }

    public func startListening() {
        guard let request = resolveCaptureRequest() else {
            return
        }

        var service = audioCaptureServiceFactory(request.source, request.deviceID)
        let client = streamingClientFactory()
        service.onLevelUpdate = { [weak self] level in
            Task { @MainActor in
                self?.updateCaptureLevel(level)
            }
        }

        service.onPCMChunk = { [weak self] chunk in
            Task {
                guard let self else {
                    return
                }

                await self.streamingChunkSender.enqueue(chunk, using: client)
            }
        }

        do {
            try service.start()
            activeCaptureMode = request.mode
            audioCaptureService = service
            streamingClient = client
            currentSession = audioChunkPipeline.beginSession(source: selectedSource, languages: languagePair)
            currentSession?.effectiveCaptureMode = request.mode
            liveTranscriptState = LiveTranscriptState(phase: .connecting)
            isListening = true
            statusText = request.mode == .systemAudioFallbackMicrophone ? "Listening with Live Audio" : "Listening for audio"
            backendStatusText = "Connecting to local FunASR backend"
            let language = languagePair.source

            streamingTask = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else {
                    return
                }

                do {
                    try await client.startSession(language: language)
                    await self.consumeStreamingEvents(from: client)
                } catch is CancellationError {
                    return
                } catch {
                    await self.handleStreamingFailure(error)
                }
            }
        } catch {
            Task {
                await client.stopSession()
            }
            streamingClient = nil
            activeCaptureMode = nil
            currentSession = nil
            liveTranscriptState = LiveTranscriptState()
            audioCaptureService = nil
            isListening = false
            statusText = request.source == .microphone ? "Microphone unavailable" : "Loopback unavailable"
            updateSetupMessage(error.localizedDescription)
        }
    }

    public func stopListening() {
        let client = streamingClient
        liveTranscriptState.phase = .stopping
        streamingTask?.cancel()
        streamingTask = nil
        streamingClient = nil
        audioCaptureService?.stop()
        audioCaptureService = nil
        activeCaptureMode = nil
        isListening = false
        captureLevel = AudioLevelSnapshot()
        statusText = "Idle"
        backendStatusText = "Backend idle"

        Task {
            await streamingChunkSender.reset()
            await client?.stopSession()
        }

        if let currentSession, currentSession.segments.isEmpty == false {
            appendHistorySession(currentSession)
        }

        currentSession = nil
        liveTranscriptState = LiveTranscriptState()
    }

    public func updateBackendStatus(_ text: String) {
        backendStatusText = text
    }

    public func updateSetupMessage(_ text: String) {
        setupMessage = text
    }

    public func refreshLoopbackDevices() {
        let devices = deviceCatalog.loopbackInputDevices()
        availableLoopbackDevices = devices

        if selectedLoopbackDeviceID == nil || devices.contains(where: { $0.id == selectedLoopbackDeviceID }) == false {
            selectedLoopbackDeviceID = devices.first?.id
        }

        if let firstDevice = devices.first {
            updateSetupMessage("Loopback device ready: \(firstDevice.name)")
        } else {
            updateSetupMessage("No virtual audio device found. Install and route system audio through the helper device.")
        }
    }

    public func selectedLoopbackDeviceName() -> String? {
        availableLoopbackDevices.first(where: { $0.id == selectedLoopbackDeviceID })?.name
    }

    public func updateCaptureLevel(_ level: AudioLevelSnapshot) {
        captureLevel = level
    }

    public func selectHistorySession(_ id: SessionRecord.ID?) {
        historyViewer.selectedSessionID = id
    }

    public func updateHistorySearch(_ text: String) {
        historyViewer.searchText = text
    }

    public func togglePiP() {
        pipState.isVisible.toggle()
    }

    public func beginFileTranscription(for fileURL: URL) {
        selectedSection = .fileTranscriber
        fileTranscription = FileTranscriptionViewState(
            phase: .processing,
            selectedFileURL: fileURL,
            progress: 0,
            currentStep: "Extracting audio channel",
            completedLines: []
        )
    }

    public func updateFileTranscriptionProgress(step: String, progress: Double) {
        fileTranscription.phase = .processing
        fileTranscription.progress = min(max(progress, 0), 1)
        fileTranscription.currentStep = step
    }

    public func completeFileTranscription(lines: [String]) {
        selectedSection = .fileTranscriber
        fileTranscription.phase = .completed
        fileTranscription.progress = 1
        fileTranscription.currentStep = nil
        fileTranscription.completedLines = lines
    }

    public func resetFileTranscription() {
        fileTranscription = FileTranscriptionViewState()
    }

    public func fileTranscriptionPreviewSteps() -> [FileTranscriptionProgress] {
        guard let selectedFileURL = fileTranscription.selectedFileURL else {
            return []
        }

        let request = fileTranscriptionService.makeRequest(fileURL: selectedFileURL, languages: languagePair)
        return fileTranscriptionService.demoProgressSequence(for: request)
    }

    private func resolveCaptureRequest() -> (source: AudioSource, deviceID: String?, mode: EffectiveCaptureMode)? {
        switch selectedSource {
        case .microphone:
            return (.microphone, nil, .microphone)
        case .systemAudio:
            if let deviceID = selectedLoopbackDeviceID {
                return (.systemAudio, deviceID, .routedSystemAudio)
            }

            return (.microphone, nil, .systemAudioFallbackMicrophone)
        case .appAudio:
            guard let deviceID = selectedLoopbackDeviceID else {
                statusText = "App Audio requires loopback"
                updateSetupMessage("Install a virtual audio device to isolate audio from a single app.")
                activeCaptureMode = .appAudioRequiresLoopback
                isListening = false
                return nil
            }

            return (.appAudio, deviceID, .appAudio)
        case .importedFile:
            return nil
        }
    }

    private static func loadAppearanceMode() -> AppearanceMode {
        guard
            let rawValue = UserDefaults.standard.string(forKey: appearanceModeDefaultsKey),
            let mode = AppearanceMode(rawValue: rawValue)
        else {
            return .system
        }

        return mode
    }

    public func loadDemoFileTranscript(for fileURL: URL) {
        beginFileTranscription(for: fileURL)

        let request = fileTranscriptionService.makeRequest(fileURL: fileURL, languages: languagePair)

        for progress in fileTranscriptionService.demoProgressSequence(for: request) {
            updateFileTranscriptionProgress(step: progress.currentStep, progress: progress.fractionCompleted)
        }

        completeFileTranscription(lines: fileTranscriptionService.demoTranscriptLines(for: request))
    }

    public func appendHistorySession(_ session: SessionRecord) {
        history.insert(session, at: 0)
    }

    public func exportHistorySRT(for session: SessionRecord) -> String? {
        historyStore?.exportSRT(for: session)
    }

    public func applyPreviewTranscript() {
        let timestamp = Date.now.timeIntervalSince1970
        let segment = TranscriptSegment(
            startedAt: timestamp,
            endedAt: timestamp + 2,
            originalText: "We can start the meeting now if everyone is ready.",
            translatedText: "Chung ta co the bat dau cuoc hop ngay bay gio."
        )

        history = [
            SessionRecord(
                source: selectedSource,
                languages: languagePair,
                segments: [segment]
            )
        ]
    }

    public var conversationRows: [ConversationRow] {
        let lines = liveTranscriptState.finalizedCaptionLines
        let timingSegments = alignedConversationSegments(for: lines.count)

        return lines.enumerated().map { index, line in
            let parsedLine = parseConversationLine(line, index: index)

            return ConversationRow(
                id: "conversation-\(index)-\(parsedLine.speaker)-\(parsedLine.text)",
                speaker: parsedLine.speaker,
                text: parsedLine.text,
                timestampLabel: conversationTimestampLabel(for: timingSegments[index]),
                isPrimarySpeaker: parsedLine.isPrimarySpeaker
            )
        }
    }

    private func persistHistory() {
        do {
            try historyStore?.save(history)
        } catch {
            // Persistence failures should not break the UI state path.
        }
    }

    private func synchronizeHistoryViewerSelection() {
        guard history.isEmpty == false else {
            historyViewer.selectedSessionID = nil
            return
        }

        if let selectedSessionID = historyViewer.selectedSessionID,
           history.contains(where: { $0.id == selectedSessionID }) {
            return
        }

        historyViewer.selectedSessionID = history.first?.id
    }

    private func alignedConversationSegments(for count: Int) -> [TranscriptSegment?] {
        guard count > 0 else {
            return []
        }

        guard let currentSession else {
            return Array(repeating: nil, count: count)
        }

        let segments = Array(currentSession.segments.suffix(count))

        guard segments.count == count else {
            return Array(repeating: nil, count: count)
        }

        return segments.map(Optional.some)
    }

    private func conversationTimestampLabel(for segment: TranscriptSegment?) -> String? {
        guard let segment else {
            return nil
        }

        return Self.conversationTimestampFormatter.string(
            from: Date(timeIntervalSince1970: segment.startedAt)
        )
    }

    private func parseConversationLine(
        _ line: String,
        index: Int
    ) -> (speaker: String, text: String, isPrimarySpeaker: Bool) {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackSpeaker = index.isMultiple(of: 2) ? "Speaker A" : "Speaker B"
        let fallbackSpeakerIsPrimary = index.isMultiple(of: 2)

        guard
            let separatorIndex = trimmedLine.firstIndex(of: ":"),
            separatorIndex > trimmedLine.startIndex
        else {
            return (
                speaker: fallbackSpeaker,
                text: trimmedLine,
                isPrimarySpeaker: fallbackSpeakerIsPrimary
            )
        }

        let speaker = trimmedLine[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let textStart = trimmedLine.index(after: separatorIndex)
        let text = trimmedLine[textStart...].trimmingCharacters(in: .whitespacesAndNewlines)

        guard speaker.isEmpty == false, text.isEmpty == false else {
            return (
                speaker: fallbackSpeaker,
                text: trimmedLine,
                isPrimarySpeaker: fallbackSpeakerIsPrimary
            )
        }

        let isPrimarySpeaker = speaker.localizedCaseInsensitiveContains("speaker a")
            || speaker.localizedCaseInsensitiveContains("host")
            || speaker.localizedCaseInsensitiveContains("interviewer")

        return (
            speaker: speaker,
            text: text,
            isPrimarySpeaker: isPrimarySpeaker || (fallbackSpeakerIsPrimary && speaker == fallbackSpeaker)
        )
    }

    private static let conversationTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    func consumeStreamingEvents(from client: any FunASRStreamingServicing) async {
        while Task.isCancelled == false {
            do {
                let event = try await client.nextEvent()
                handleStreamingEvent(event)

                if case .closed = event {
                    break
                }
            } catch is CancellationError {
                break
            } catch {
                handleStreamingFailure(error)
                break
            }
        }
    }

    func handleStreamingEvent(_ event: FunASRStreamingEvent) {
        switch event {
        case .ready:
            liveTranscriptState.phase = .streaming
            backendStatusText = "Backend streaming"
            let client = streamingClient
            Task {
                await streamingChunkSender.markReady(using: client)
            }
        case .partial(let text):
            liveTranscriptState.applyPartial(text)
            statusText = "Receiving partial subtitles"
        case .final(let text):
            liveTranscriptState.applyFinal(text)

            if let currentSession {
                self.currentSession = audioChunkPipeline.appendChunk(
                    data: Data(),
                    transcript: text,
                    translation: nil,
                    to: currentSession
                )
            }
        case .error(let message):
            handleStreamingFailure(StreamingFailure.message(message))
        case .closed:
            completeStreamingSession(backendStatus: "Backend closed")
        }
    }

    func handleStreamingFailure(_ error: Error) {
        audioCaptureService?.stop()
        audioCaptureService = nil
        streamingTask?.cancel()
        streamingTask = nil
        streamingClient = nil
        activeCaptureMode = nil
        isListening = false
        captureLevel = AudioLevelSnapshot()
        statusText = "Idle"
        liveTranscriptState.phase = .degraded
        liveTranscriptState.lastError = error.localizedDescription
        backendStatusText = "Streaming failed"
        Task {
            await streamingChunkSender.reset()
        }

        if let currentSession, currentSession.segments.isEmpty == false {
            appendHistorySession(currentSession)
        }

        currentSession = nil
    }

    func completeStreamingSession(backendStatus: String) {
        audioCaptureService?.stop()
        audioCaptureService = nil
        streamingTask = nil
        streamingClient = nil
        activeCaptureMode = nil
        isListening = false
        captureLevel = AudioLevelSnapshot()
        statusText = "Idle"
        backendStatusText = backendStatus
        liveTranscriptState.phase = .idle
        Task {
            await streamingChunkSender.reset()
        }

        if let currentSession, currentSession.segments.isEmpty == false {
            appendHistorySession(currentSession)
        }

        currentSession = nil
    }
}

private extension AppStore {
    actor StreamingChunkSender {
        private var isReady = false
        private var pendingChunks: [Data] = []

        func enqueue(_ chunk: Data, using client: any FunASRStreamingServicing) async {
            if isReady {
                try? await client.sendAudioChunk(chunk)
                return
            }

            pendingChunks.append(chunk)
        }

        func markReady(using client: (any FunASRStreamingServicing)?) async {
            isReady = true

            guard let client else {
                return
            }

            for chunk in pendingChunks {
                try? await client.sendAudioChunk(chunk)
            }

            pendingChunks.removeAll(keepingCapacity: false)
        }

        func reset() {
            isReady = false
            pendingChunks.removeAll(keepingCapacity: false)
        }
    }

    enum StreamingFailure: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let message):
                return message
            }
        }
    }

    static func makeDefaultHistoryStore() -> HistoryStore? {
        guard let fileURL = try? AppPaths.historyFileURL() else {
            return nil
        }

        return HistoryStore(fileURL: fileURL)
    }

    static func makeDefaultDeviceCatalog() -> AudioDeviceCatalog {
        AudioDeviceCatalog.systemDefault()
    }

    static func defaultSetupMessage() -> String {
        let permissions = PermissionsService().currentSnapshot()

        guard permissions.microphoneAuthorized else {
            return "Microphone access is required before live subtitles can start."
        }

        return VirtualDeviceDiagnostics(availableDeviceNames: []).currentStatus().message
    }
}

public extension AppStore {
    static var preview: AppStore { AppStore() }
}
