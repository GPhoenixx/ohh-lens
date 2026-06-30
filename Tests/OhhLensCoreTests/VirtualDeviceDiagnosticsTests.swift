import XCTest
@testable import OhhLens

final class VirtualDeviceDiagnosticsTests: XCTestCase {
    func test_missingVirtualDeviceReturnsNeedsAttentionMessage() {
        let diagnostics = VirtualDeviceDiagnostics(availableDeviceNames: [])

        let result = diagnostics.currentStatus()

        XCTAssertEqual(result.state, .needsAttention)
        XCTAssertTrue(result.message.contains("virtual audio device"))
    }
}
