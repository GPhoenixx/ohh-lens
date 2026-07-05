import Foundation

public struct ConversationRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let speaker: String
    public let text: String
    public let timestampLabel: String?
    public let isPrimarySpeaker: Bool

    public init(
        id: String,
        speaker: String,
        text: String,
        timestampLabel: String?,
        isPrimarySpeaker: Bool
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.timestampLabel = timestampLabel
        self.isPrimarySpeaker = isPrimarySpeaker
    }
}
