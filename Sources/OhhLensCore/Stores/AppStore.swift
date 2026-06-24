import Foundation
import Observation

@MainActor
@Observable
public final class AppStore {
    public var selectedSection: AppSection = .live
    public var selectedSource: AudioSource = .microphone
    public var captionMode: CaptionMode = .dualLine
    public var languagePair = LanguagePair(source: "auto", target: "en")
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

    public init() {
        self.historyStore = AppStore.makeDefaultHistoryStore()
        self.setupMessage = AppStore.defaultSetupMessage()

        if let historyStore {
            self.history = (try? historyStore.load()) ?? []
        } else {
            self.history = []
        }
    }

    public init(historyStore: HistoryStore?) {
        self.historyStore = historyStore
        self.setupMessage = AppStore.defaultSetupMessage()

        if let historyStore {
            self.history = (try? historyStore.load()) ?? []
        } else {
            self.history = []
        }
    }

    public func startListening() {
        isListening = true
        statusText = "Listening"
    }

    public func stopListening() {
        isListening = false
        statusText = "Idle"
    }

    public func updateBackendStatus(_ text: String) {
        backendStatusText = text
    }

    public func updateSetupMessage(_ text: String) {
        setupMessage = text
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
