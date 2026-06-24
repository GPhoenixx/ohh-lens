public enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case live = "Live"
    case history = "History"
    case files = "Files"
    case setup = "Setup"

    public var id: Self { self }
}
