import Foundation
import Observation

@MainActor
@Observable
public final class AppStore {
    public var selectedSection: AppSection = .live
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
    public var history: [SessionRecord] = [] {
        didSet {
            persistHistory()
        }
    }

    private let historyStore: HistoryStore?
    private let audioChunkPipeline = AudioChunkPipeline()
    private let deviceCatalog: AudioDeviceCatalog
    private let loopbackCaptureServiceFactory: (AudioSource, String?) -> LoopbackCaptureService
    private let streamingClientFactory: () -> any FunASRStreamingServicing
    private let streamingChunkSender = StreamingChunkSender()
    private var loopbackCaptureService: LoopbackCaptureService?
    private var streamingTask: Task<Void, Never>?
    private var streamingClient: (any FunASRStreamingServicing)?
    private var currentSession: SessionRecord?

    public init() {
        self.historyStore = AppStore.makeDefaultHistoryStore()
        self.deviceCatalog = AppStore.makeDefaultDeviceCatalog()
        self.loopbackCaptureServiceFactory = { source, deviceID in
            LoopbackCaptureService(source: source, deviceID: deviceID)
        }
        self.streamingClientFactory = { FunASRStreamingClient() }
        self.setupMessage = AppStore.defaultSetupMessage()

        if let historyStore {
            self.history = (try? historyStore.load()) ?? []
        } else {
            self.history = []
        }

        refreshLoopbackDevices()
    }

    public init(
        historyStore: HistoryStore?,
        deviceCatalog: AudioDeviceCatalog = .init(),
        loopbackCaptureServiceFactory: @escaping (AudioSource, String?) -> LoopbackCaptureService = { source, deviceID in
            LoopbackCaptureService(source: source, deviceID: deviceID)
        },
        streamingClientFactory: @escaping () -> any FunASRStreamingServicing = { FunASRStreamingClient() }
    ) {
        self.historyStore = historyStore
        self.deviceCatalog = deviceCatalog
        self.loopbackCaptureServiceFactory = loopbackCaptureServiceFactory
        self.streamingClientFactory = streamingClientFactory
        self.setupMessage = AppStore.defaultSetupMessage()

        if let historyStore {
            self.history = (try? historyStore.load()) ?? []
        } else {
            self.history = []
        }

        refreshLoopbackDevices()
    }

    public func startListening() {
        if selectedSource == .systemAudio || selectedSource == .appAudio {
            guard let selectedLoopbackDeviceID else {
                statusText = "No loopback device"
                isListening = false
                return
            }

            let service = loopbackCaptureServiceFactory(selectedSource, selectedLoopbackDeviceID)
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
                loopbackCaptureService = service
                streamingClient = client
                currentSession = audioChunkPipeline.beginSession(source: selectedSource, languages: languagePair)
                liveTranscriptState = LiveTranscriptState(phase: .connecting)
                isListening = true
                statusText = "Listening for audio"
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
                currentSession = nil
                liveTranscriptState = LiveTranscriptState()
                loopbackCaptureService = nil
                isListening = false
                statusText = "Loopback unavailable"
                updateSetupMessage(error.localizedDescription)
            }
            return
        }

        isListening = true
        statusText = "Listening"
    }

    public func stopListening() {
        let client = streamingClient
        liveTranscriptState.phase = .stopping
        streamingTask?.cancel()
        streamingTask = nil
        streamingClient = nil
        loopbackCaptureService?.stop()
        loopbackCaptureService = nil
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

    private func persistHistory() {
        do {
            try historyStore?.save(history)
        } catch {
            // Persistence failures should not break the UI state path.
        }
    }

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
        loopbackCaptureService?.stop()
        loopbackCaptureService = nil
        streamingTask?.cancel()
        streamingTask = nil
        streamingClient = nil
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
        loopbackCaptureService?.stop()
        loopbackCaptureService = nil
        streamingTask = nil
        streamingClient = nil
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
