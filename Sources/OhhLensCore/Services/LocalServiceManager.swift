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
    private let maxHealthCheckAttempts: Int
    private let healthCheckDelayNanoseconds: UInt64
    private var operationGeneration = 0

    public init(
        processRunner: ProcessRunning,
        client: FunASRServicing,
        maxHealthCheckAttempts: Int = 3,
        healthCheckDelayNanoseconds: UInt64 = 250_000_000
    ) {
        self.processRunner = processRunner
        self.client = client
        self.maxHealthCheckAttempts = max(1, maxHealthCheckAttempts)
        self.healthCheckDelayNanoseconds = healthCheckDelayNanoseconds
    }

    public func start() async throws {
        operationGeneration += 1
        let generation = operationGeneration
        status = .starting

        processRunner.terminate()

        do {
            try processRunner.launch(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["bash", "-lc", "echo starting-funasr"]
            )
        } catch {
            guard generation == operationGeneration else { throw error }
            status = .needsAttention("Failed to launch FunASR service")
            throw error
        }

        for attempt in 1...maxHealthCheckAttempts {
            guard generation == operationGeneration else { return }

            if await client.healthCheck() {
                guard generation == operationGeneration else { return }
                status = .ready
                return
            }

            guard generation == operationGeneration else { return }

            if attempt < maxHealthCheckAttempts, healthCheckDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: healthCheckDelayNanoseconds)
            }
        }

        if generation == operationGeneration, status != .ready {
            status = .needsAttention("FunASR health check failed")
        }
    }

    public func stop() {
        operationGeneration += 1
        processRunner.terminate()
        status = .idle
    }
}
