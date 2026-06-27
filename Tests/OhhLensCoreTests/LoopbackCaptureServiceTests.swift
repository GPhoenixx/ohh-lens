import XCTest
import AVFoundation
@testable import OhhLensCore

final class LoopbackCaptureServiceTests: XCTestCase {
    func test_pcmConversionProducesBackendReady16kMonoInt16ChunkFrom48kStereoFloat() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 2,
                interleaved: false
            )
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: 480
            )
        )
        buffer.frameLength = 480

        let channelData = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0..<480 {
            channelData[0][frame] = 0.5
            channelData[1][frame] = 0.25
        }

        let chunk = try XCTUnwrap(LoopbackCaptureService.pcmS16Mono16kChunk(from: buffer))

        XCTAssertEqual(chunk.count, 320)
        XCTAssertNotEqual(chunk, Data(repeating: 0, count: 320))
    }

    func test_testDoublePublishesPCMChunks() {
        let service = LoopbackCaptureService.testDouble(source: .systemAudio)
        let recorder = ChunkRecorder()

        service.onPCMChunk = { chunk in
            recorder.chunks.append(chunk)
        }

        service.receiveTestPCMChunk(Data([0x01, 0x02, 0x03, 0x04]))

        XCTAssertEqual(recorder.chunks, [Data([0x01, 0x02, 0x03, 0x04])])
    }

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

private final class ChunkRecorder: @unchecked Sendable {
    var chunks: [Data] = []
}
