import Foundation

public enum AppPaths {
    public static func supportDirectory(fileManager: FileManager = .default) throws -> URL {
        let baseDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return baseDirectory.appendingPathComponent("OhhLens", isDirectory: true)
    }

    public static func historyFileURL(fileManager: FileManager = .default) throws -> URL {
        try supportDirectory(fileManager: fileManager)
            .appendingPathComponent("history.json", isDirectory: false)
    }
}
