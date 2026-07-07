public enum AudioSource: String, CaseIterable, Codable, Identifiable {
    case microphone
    case systemAudio
    case appAudio
    case importedFile

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .microphone:
            return "Microphone"
        case .systemAudio:
            return "System Audio"
        case .appAudio:
            return "App Audio"
        case .importedFile:
            return "Imported File"
        }
    }

    public var displayDescription: String {
        switch self {
        case .microphone:
            return "Uses your real input device. Best for direct speech capture."
        case .systemAudio:
            return "Uses loopback when available, otherwise falls back to microphone."
        case .appAudio:
            return "Requires a loopback device."
        case .importedFile:
            return "Uses audio from an imported media file instead of live capture."
        }
    }
}
