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

    public init() {}

    public func startListening() {
        isListening = true
        statusText = "Listening"
    }

    public func stopListening() {
        isListening = false
        statusText = "Idle"
    }
}

public extension AppStore {
    static var preview: AppStore { AppStore() }
}
