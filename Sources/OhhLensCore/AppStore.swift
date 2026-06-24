import Observation

@MainActor
@Observable
public final class AppStore {
    public var selectedSection: AppSection

    public init(selectedSection: AppSection = .live) {
        self.selectedSection = selectedSection
    }
}
