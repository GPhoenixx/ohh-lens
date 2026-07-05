import Foundation

public struct FileTranscriptionViewState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case processing
        case completed
    }

    public var phase: Phase
    public var selectedFileURL: URL?
    public var progress: Double
    public var currentStep: String?
    public var completedLines: [String]

    public init(
        phase: Phase = .idle,
        selectedFileURL: URL? = nil,
        progress: Double = 0,
        currentStep: String? = nil,
        completedLines: [String] = []
    ) {
        self.phase = phase
        self.selectedFileURL = selectedFileURL
        self.progress = progress
        self.currentStep = currentStep
        self.completedLines = completedLines
    }
}
