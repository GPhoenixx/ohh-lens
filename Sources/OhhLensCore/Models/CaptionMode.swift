public enum CaptionMode: String, CaseIterable, Identifiable {
    case originalOnly
    case translationOnly
    case dualLine

    public var id: String { rawValue }
}
