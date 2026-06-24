import Foundation

public final class HistoryStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(baseDirectory: URL, fileManager: FileManager = .default) {
        self.fileURL = baseDirectory.appendingPathComponent("history.json", isDirectory: false)
        self.fileManager = fileManager
    }

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func save(_ sessions: [SessionRecord]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let data = try encoder.encode(sessions)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() throws -> [SessionRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([SessionRecord].self, from: data)
    }

    public func exportSRT(for session: SessionRecord) -> String {
        session.segments.enumerated().map { index, segment in
            let translatedBlock = segment.translatedText.map { "\n\($0)" } ?? ""

            return """
            \(index + 1)
            \(formatTimecode(segment.startedAt)) --> \(formatTimecode(segment.endedAt))
            \(segment.originalText)\(translatedBlock)
            """
        }
        .joined(separator: "\n\n")
    }

    private func formatTimecode(_ interval: TimeInterval) -> String {
        let roundedMilliseconds = Int((interval * 1_000).rounded())
        let hours = roundedMilliseconds / 3_600_000
        let minutes = (roundedMilliseconds % 3_600_000) / 60_000
        let seconds = (roundedMilliseconds % 60_000) / 1_000
        let milliseconds = roundedMilliseconds % 1_000

        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
}
