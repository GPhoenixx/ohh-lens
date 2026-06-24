public enum AudioSource: String, CaseIterable, Codable, Identifiable {
    case microphone
    case systemAudio
    case appAudio
    case importedFile

    public var id: String { rawValue }
}
