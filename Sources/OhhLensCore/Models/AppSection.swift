public enum AppSection: String, CaseIterable, Identifiable {
    case live
    case history
    case files
    case setup

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}
