import XCTest
@testable import OhhLensCore

final class LocalServiceManagerTests: XCTestCase {
    @MainActor
    func test_startTransitionsToReadyWhenHealthCheckSucceeds() async throws {
        let runner = StubProcessRunner()
        let client = StubFunASRClient(healthResults: [true])
        let manager = LocalServiceManager(
            processRunner: runner,
            client: client,
            maxHealthCheckAttempts: 1,
            healthCheckDelayNanoseconds: 0
        )

        try await manager.start()

        XCTAssertEqual(manager.status, LocalServiceManager.Status.ready)
        XCTAssertEqual(runner.launchCount, 1)
    }

    @MainActor
    func test_startTransitionsToNeedsAttentionWhenHealthChecksFail() async throws {
        let runner = StubProcessRunner()
        let client = StubFunASRClient(healthResults: [false, false, false])
        let manager = LocalServiceManager(
            processRunner: runner,
            client: client,
            maxHealthCheckAttempts: 3,
            healthCheckDelayNanoseconds: 0
        )

        try await manager.start()
        let healthCheckCount = await client.healthCheckCount

        XCTAssertEqual(manager.status, LocalServiceManager.Status.needsAttention("FunASR health check failed"))
        XCTAssertEqual(runner.launchCount, 1)
        XCTAssertEqual(healthCheckCount, 3)
    }

    @MainActor
    func test_startTransitionsToNeedsAttentionWhenLaunchThrows() async {
        let runner = StubProcessRunner(launchError: StubProcessRunnerError.launchFailed)
        let client = StubFunASRClient(healthResults: [true])
        let manager = LocalServiceManager(
            processRunner: runner,
            client: client,
            maxHealthCheckAttempts: 1,
            healthCheckDelayNanoseconds: 0
        )

        do {
            try await manager.start()
            XCTFail("Expected launch to throw")
        } catch {}
        let healthCheckCount = await client.healthCheckCount

        XCTAssertEqual(manager.status, LocalServiceManager.Status.needsAttention("Failed to launch FunASR service"))
        XCTAssertEqual(healthCheckCount, 0)
    }

    @MainActor
    func test_stopReturnsManagerToIdle() async throws {
        let runner = StubProcessRunner()
        let client = StubFunASRClient(healthResults: [true])
        let manager = LocalServiceManager(
            processRunner: runner,
            client: client,
            maxHealthCheckAttempts: 1,
            healthCheckDelayNanoseconds: 0
        )

        try await manager.start()
        manager.stop()

        XCTAssertEqual(manager.status, LocalServiceManager.Status.idle)
        XCTAssertEqual(runner.terminateCount, 1)
    }

    @MainActor
    func test_repeatedStartRelaunchesProcessSafely() async throws {
        let runner = StubProcessRunner()
        let client = StubFunASRClient(healthResults: [true, true])
        let manager = LocalServiceManager(
            processRunner: runner,
            client: client,
            maxHealthCheckAttempts: 1,
            healthCheckDelayNanoseconds: 0
        )

        try await manager.start()
        try await manager.start()

        XCTAssertEqual(manager.status, LocalServiceManager.Status.ready)
        XCTAssertEqual(runner.launchCount, 2)
        XCTAssertEqual(runner.terminateCount, 1)
    }
}

private final class StubProcessRunner: ProcessRunning {
    var launchCount = 0
    var terminateCount = 0
    private let launchError: Error?
    private var isRunning = false

    init(launchError: Error? = nil) {
        self.launchError = launchError
    }

    func launch(executableURL: URL, arguments: [String]) throws {
        if let launchError {
            throw launchError
        }
        launchCount += 1
        isRunning = true
    }

    func terminate() {
        guard isRunning else { return }
        terminateCount += 1
        isRunning = false
    }
}

private actor StubHealthCheckCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private struct StubFunASRClient: FunASRServicing {
    let healthResults: [Bool]
    private let counter = StubHealthCheckCounter()

    var healthCheckCount: Int {
        get async {
            await counter.value()
        }
    }

    func healthCheck() async -> Bool {
        await counter.increment()
        let currentCount = await counter.value()
        let index = min(currentCount - 1, healthResults.count - 1)
        return healthResults[index]
    }
}

private enum StubProcessRunnerError: Error {
    case launchFailed
}
