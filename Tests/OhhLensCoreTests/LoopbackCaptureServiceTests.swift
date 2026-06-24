import XCTest
@testable import OhhLensCore

final class LoopbackCaptureServiceTests: XCTestCase {
    func test_catalogReturnsLikelyVirtualDevicesFirst() {
        let catalog = AudioDeviceCatalog(
            devices: [
                .init(id: "built-in", name: "MacBook Pro Microphone", isInput: true),
                .init(id: "blackhole", name: "BlackHole 2ch", isInput: true),
                .init(id: "vb", name: "VB-Cable", isInput: true)
            ]
        )

        let devices = catalog.loopbackInputDevices()

        XCTAssertEqual(devices.map(\.id), ["blackhole", "vb"])
    }

    @MainActor
    func test_serviceMarksAudioDetectedWhenSamplePowerExceedsThreshold() {
        let service = LoopbackCaptureService.testDouble(source: .systemAudio)

        service.receiveTestPower(average: -18, peak: -8)

        XCTAssertTrue(service.currentLevel.detectedSound)
    }
}
