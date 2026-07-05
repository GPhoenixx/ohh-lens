public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case liveSubtitles
    case conversations
    case fileTranscriber
    case savedTranscripts
    case appSettings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .liveSubtitles:
            "Live Subtitles"
        case .conversations:
            "Conversations"
        case .fileTranscriber:
            "File Transcriber"
        case .savedTranscripts:
            "Saved Transcripts"
        case .appSettings:
            "App Settings"
        }
    }
}
