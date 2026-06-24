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
        status = .starting

        processRunner.terminate()

        do {
            try processRunner.launch(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["bash", "-lc", "echo starting-funasr"]
            )
        } catch {
            status = .needsAttention("Failed to launch FunASR service")
            throw error
        }

        for attempt in 1...maxHealthCheckAttempts {
            if await client.healthCheck() {
                status = .ready
                return
            }

            if attempt < maxHealthCheckAttempts, healthCheckDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: healthCheckDelayNanoseconds)
            }
        }

        if status != .ready {
            status = .needsAttention("FunASR health check failed")
        }
    }

    public func stop() {
        processRunner.terminate()
        status = .idle
    }
}
