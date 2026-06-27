import Foundation

public struct LiveTranscriptState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case connecting
        case streaming
        case degraded
        case stopping
    }

    public var phase: Phase
    public var partialText: String
    public var finalText: String
    public var finalizedCaptionLines: [String]
    public var lastError: String?

    public var visibleCaptionLines: [String] {
        var lines = Array(finalizedCaptionLines.suffix(2))
        let draftText = partialText.trimmingCharacters(in: .whitespacesAndNewlines)

        if draftText.isEmpty == false {
            lines = Array(lines.suffix(1))
            lines.append(draftText)
        }

        return Array(lines.suffix(2))
    }

    public init(
        phase: Phase = .idle,
        partialText: String = "",
        finalText: String = "",
        finalizedCaptionLines: [String] = [],
        lastError: String? = nil
    ) {
        self.phase = phase
        self.partialText = partialText
        self.finalText = finalText
        self.finalizedCaptionLines = finalizedCaptionLines
        self.lastError = lastError
    }

    public mutating func applyPartial(_ text: String) {
        let incomingText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentText = partialText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard incomingText.isEmpty == false else {
            return
        }

        if currentText.isEmpty || incomingText.hasPrefix(currentText) {
            partialText = incomingText
        } else if currentText.hasSuffix(incomingText) {
            partialText = currentText
        } else {
            partialText = "\(currentText) \(incomingText)"
        }
    }

    public mutating func applyFinal(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        partialText = ""
        finalText = trimmedText

        guard trimmedText.isEmpty == false else {
            return
        }

        finalizedCaptionLines.append(trimmedText)
        finalizedCaptionLines = Array(finalizedCaptionLines.suffix(2))
    }
}
