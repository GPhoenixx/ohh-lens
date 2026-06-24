import Foundation

public protocol ProcessRunning {
    func launch(executableURL: URL, arguments: [String]) throws
    func terminate()
}

public final class ProcessRunner: ProcessRunning {
    private var process: Process?

    public init() {}

    public func launch(executableURL: URL, arguments: [String]) throws {
        terminate()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        try process.run()
        self.process = process
    }

    public func terminate() {
        guard let process else { return }
        defer { self.process = nil }
        guard process.isRunning else { return }
        process.terminate()
    }
}
