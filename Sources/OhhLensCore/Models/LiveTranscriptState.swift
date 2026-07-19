import Foundation

public struct LiveSubtitlePair: Equatable, Sendable, Identifiable {
    public let id: String
    public let segmentID: String
    public let englishText: String
    public let vietnameseText: String

    public init(
        id: String,
        segmentID: String,
        englishText: String,
        vietnameseText: String
    ) {
        self.id = id
        self.segmentID = segmentID
        self.englishText = englishText
        self.vietnameseText = vietnameseText
    }
}

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
    public var activeSegmentID: String?
    public var currentVietnameseText: String
    public var translatedCaptionPairs: [LiveSubtitlePair]

    public var visibleTranslationLine: String? {
        let trimmed = currentVietnameseText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public var untranslatedDraftText: String? {
        let draftText = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draftText.isEmpty == false else { return nil }

        let translatedPrefix = translatedCaptionPairs
            .filter { $0.segmentID == activeSegmentID }
            .map(\.englishText)
            .joined(separator: " ")

        guard translatedPrefix.isEmpty == false, draftText.hasPrefix(translatedPrefix) else {
            return draftText
        }

        let suffix = draftText.dropFirst(translatedPrefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? nil : suffix
    }

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
        lastError: String? = nil,
        activeSegmentID: String? = nil,
        currentVietnameseText: String = "",
        translatedCaptionPairs: [LiveSubtitlePair] = []
    ) {
        self.phase = phase
        self.partialText = partialText
        self.finalText = finalText
        self.finalizedCaptionLines = finalizedCaptionLines
        self.lastError = lastError
        self.activeSegmentID = activeSegmentID
        self.currentVietnameseText = currentVietnameseText
        self.translatedCaptionPairs = translatedCaptionPairs
    }

    public mutating func applyPartial(_ text: String) {
        applyPartial(segmentID: activeSegmentID ?? "legacy-segment", text: text)
    }

    public mutating func applyPartial(segmentID: String, text: String) {
        if activeSegmentID != segmentID {
            activeSegmentID = segmentID
            partialText = ""
            currentVietnameseText = ""
        }

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
        applyFinal(segmentID: activeSegmentID ?? "legacy-segment", text: text)
    }

    public mutating func applyFinal(segmentID: String, text: String) {
        if activeSegmentID != segmentID {
            activeSegmentID = segmentID
            currentVietnameseText = ""
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        partialText = ""
        finalText = trimmedText

        guard trimmedText.isEmpty == false else {
            return
        }

        finalizedCaptionLines.append(trimmedText)
        finalizedCaptionLines = Array(finalizedCaptionLines.suffix(2))
    }

    public mutating func applyTranslation(
        segmentID: String,
        translationID: String,
        sourceText: String,
        translatedText: String
    ) {
        currentVietnameseText = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)

        let pair = LiveSubtitlePair(
            id: translationID,
            segmentID: segmentID,
            englishText: sourceText,
            vietnameseText: currentVietnameseText
        )
        if let index = translatedCaptionPairs.firstIndex(where: { $0.id == translationID }) {
            translatedCaptionPairs[index] = pair
        } else {
            translatedCaptionPairs.append(pair)
        }
    }
}
