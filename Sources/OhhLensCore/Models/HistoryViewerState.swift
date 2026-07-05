import Foundation

public struct HistoryViewerState: Equatable, Sendable {
    public var selectedSessionID: SessionRecord.ID?
    public var searchText: String
    public var translationTarget: String

    public init(
        selectedSessionID: SessionRecord.ID? = nil,
        searchText: String = "",
        translationTarget: String = "none"
    ) {
        self.selectedSessionID = selectedSessionID
        self.searchText = searchText
        self.translationTarget = translationTarget
    }
}
