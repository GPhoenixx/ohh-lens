import Foundation

public struct FileTranscriptionRequest {
    public let fileURL: URL
    public let languages: LanguagePair

    public init(fileURL: URL, languages: LanguagePair) {
        self.fileURL = fileURL
        self.languages = languages
    }
}

public final class FileTranscriptionService {
    public init() {}

    public func makeRequest(fileURL: URL, languages: LanguagePair) -> FileTranscriptionRequest {
        FileTranscriptionRequest(fileURL: fileURL, languages: languages)
    }
}
