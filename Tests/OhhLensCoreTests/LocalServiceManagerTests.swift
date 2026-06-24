import XCTest
@testable import OhhLensCore

final class LocalServiceManagerTests: XCTestCase {
    @MainActor
    func test_startTransitionsToReadyWhenHealthCheckSucceeds() async throws {
        let runner = StubProcessRunner()
        let client = StubFunASRClient(healthResult: true)
        let manager = LocalServiceManager(processRunner: runner, client: client)

        try await manager.start()

        XCTAssertEqual(manager.status, .ready)
        XCTAssertEqual(runner.launchCount, 1)
    }
}

private final class StubProcessRunner: ProcessRunning {
    var launchCount = 0

    func launch(executableURL: URL, arguments: [String]) throws {
        launchCount += 1
    }

    func terminate() {}
}

private struct StubFunASRClient: FunASRServicing {
    let healthResult: Bool

    func healthCheck() async -> Bool {
        healthResult
    }
}
