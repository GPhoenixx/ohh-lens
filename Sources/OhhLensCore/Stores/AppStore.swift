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
    public var history: [SessionRecord] = [] {
        didSet {
            persistHistory()
        }
    }

    private let historyStore: HistoryStore?

    public init() {
        self.historyStore = AppStore.makeDefaultHistoryStore()

        if let historyStore {
            self.history = (try? historyStore.load()) ?? []
        } else {
            self.history = []
        }
    }

    public init(historyStore: HistoryStore?) {
        self.historyStore = historyStore

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

    public func appendHistorySession(_ session: SessionRecord) {
        history.insert(session, at: 0)
    }

    public func exportHistorySRT(for session: SessionRecord) -> String? {
        historyStore?.exportSRT(for: session)
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
}

public extension AppStore {
    static var preview: AppStore { AppStore() }
}
