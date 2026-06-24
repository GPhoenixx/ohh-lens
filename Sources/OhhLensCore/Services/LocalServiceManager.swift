import Foundation
import Observation

@MainActor
@Observable
public final class LocalServiceManager {
    public enum Status: Equatable {
        case idle
        case starting
        case ready
        case needsAttention(String)
    }

    public private(set) var status: Status = .idle

    private let processRunner: ProcessRunning
    private let client: FunASRServicing

    public init(processRunner: ProcessRunning, client: FunASRServicing) {
        self.processRunner = processRunner
        self.client = client
    }

    public func start() async throws {
        status = .starting
        try processRunner.launch(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["bash", "-lc", "echo starting-funasr"]
        )

        if await client.healthCheck() {
            status = .ready
        } else {
            status = .needsAttention("FunASR health check failed")
        }
    }

    public func stop() {
        processRunner.terminate()
        status = .idle
    }
}
