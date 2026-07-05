import Foundation

public struct FileTranscriptionRequest {
    public let fileURL: URL
    public let languages: LanguagePair

    public init(fileURL: URL, languages: LanguagePair) {
        self.fileURL = fileURL
        self.languages = languages
    }
}

public struct FileTranscriptionProgress: Equatable, Sendable {
    public var fractionCompleted: Double
    public var currentStep: String

    public init(fractionCompleted: Double, currentStep: String) {
        self.fractionCompleted = fractionCompleted
        self.currentStep = currentStep
    }
}

public final class FileTranscriptionService {
    public init() {}

    public func makeRequest(fileURL: URL, languages: LanguagePair) -> FileTranscriptionRequest {
        FileTranscriptionRequest(fileURL: fileURL, languages: languages)
    }

    public func demoProgressSequence(for request: FileTranscriptionRequest) -> [FileTranscriptionProgress] {
        let isVideoFile = ["mp4", "mov", "mkv"].contains(request.fileURL.pathExtension.lowercased())

        return [
            .init(fractionCompleted: 0.18, currentStep: isVideoFile ? "Extracting audio channel" : "Loading waveform data"),
            .init(fractionCompleted: 0.57, currentStep: "Running speech recognition"),
            .init(fractionCompleted: 0.86, currentStep: "Aligning timestamps and translation"),
        ]
    }

    public func demoTranscriptLines(for request: FileTranscriptionRequest) -> [String] {
        let stem = request.fileURL.deletingPathExtension().lastPathComponent

        return [
            "Imported file: \(stem)",
            "This staged preview mirrors the local transcription pipeline while native processing hooks are still being wired.",
            "Progress, results, and export affordances are now driven by explicit File Transcriber state."
        ]
    }
}
