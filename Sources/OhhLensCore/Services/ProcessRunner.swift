import Foundation

public protocol ProcessRunning {
    func launch(executableURL: URL, arguments: [String]) throws
    func terminate()
}

public final class ProcessRunner: ProcessRunning {
    private let process = Process()

    public init() {}

    public func launch(executableURL: URL, arguments: [String]) throws {
        process.executableURL = executableURL
        process.arguments = arguments
        try process.run()
    }

    public func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }
}
