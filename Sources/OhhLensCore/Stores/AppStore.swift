import Foundation
import Observation

@MainActor
@Observable
public final class AppStore {
    public var selectedSection: AppSection = .live
    public var selectedSource: AudioSource = .microphone
    public var captionMode: CaptionMode = .dualLine
    public var languagePair = LanguagePair(source: "auto", target: "en")
    public var availableLoopbackDevices: [AudioInputDevice] = []
    public var selectedLoopbackDeviceID: String?
    public var captureLevel = AudioLevelSnapshot()
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
    private let deviceCatalog: AudioDeviceCatalog
    private let loopbackCaptureServiceFactory: (AudioSource, String?) -> LoopbackCaptureService
    private var loopbackCaptureService: LoopbackCaptureService?

    public init() {
        self.historyStore = AppStore.makeDefaultHistoryStore()
        self.deviceCatalog = AppStore.makeDefaultDeviceCatalog()
        self.loopbackCaptureServiceFactory = { source, deviceID in
            LoopbackCaptureService(source: source, deviceID: deviceID)
        }
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
        }
    ) {
        self.historyStore = historyStore
        self.deviceCatalog = deviceCatalog
        self.loopbackCaptureServiceFactory = loopbackCaptureServiceFactory
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
            service.onLevelUpdate = { [weak self] level in
                Task { @MainActor in
                    self?.updateCaptureLevel(level)
                }
            }

            do {
                try service.start()
                loopbackCaptureService = service
                isListening = true
                statusText = "Listening for audio"
            } catch {
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
        loopbackCaptureService?.stop()
        loopbackCaptureService = nil
        isListening = false
        captureLevel = AudioLevelSnapshot()
        statusText = "Idle"
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

        guard selectedSource == .systemAudio || selectedSource == .appAudio else {
            return
        }

        statusText = level.detectedSound ? "Audio detected" : "Listening for audio"
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
}

private extension AppStore {
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
