import AVFoundation
import CoreMedia
import Foundation

public final class LoopbackCaptureService: NSObject, AudioCaptureServicing {
    public let source: AudioSource
    public private(set) var currentLevel = AudioLevelSnapshot()
    public var onLevelUpdate: (@Sendable (AudioLevelSnapshot) -> Void)?
    public var onPCMChunk: (@Sendable (Data) -> Void)?

    private let deviceID: String?
    private let isTestDouble: Bool
    private let captureQueue = DispatchQueue(label: "com.ohhlens.loopback-capture")
    private var captureSession: AVCaptureSession?
    private var sampleBufferDelegate: SampleBufferDelegate?

    public init(source: AudioSource, deviceID: String? = nil) {
        self.source = source
        self.deviceID = deviceID
        self.isTestDouble = false
    }

    private init(source: AudioSource, isTestDouble: Bool) {
        self.source = source
        self.deviceID = nil
        self.isTestDouble = isTestDouble
    }

    public func start() throws {
        guard isTestDouble == false else {
            return
        }

        guard captureSession == nil else {
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()

        let device = try resolvedDevice()
        let input = try AVCaptureDeviceInput(device: device)

        guard session.canAddInput(input) else {
            throw LoopbackCaptureError.cannotAddInput
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        let delegate = SampleBufferDelegate { [weak self] sampleBuffer in
            self?.handleSampleBuffer(sampleBuffer)
        }
        output.setSampleBufferDelegate(delegate, queue: captureQueue)

        guard session.canAddOutput(output) else {
            throw LoopbackCaptureError.cannotAddOutput
        }
        session.addOutput(output)

        session.commitConfiguration()
        session.startRunning()

        captureSession = session
        sampleBufferDelegate = delegate
    }

    public func stop() {
        captureSession?.stopRunning()
        captureSession = nil
        sampleBufferDelegate = nil
        publish(level: AudioLevelSnapshot())
    }

    static func testDouble(source: AudioSource) -> LoopbackCaptureService {
        LoopbackCaptureService(source: source, isTestDouble: true)
    }

    func receiveTestPower(average: Float, peak: Float) {
        publish(level: Self.makeLevelSnapshot(average: average, peak: peak))
    }

    func receiveTestPCMChunk(_ data: Data) {
        onPCMChunk?(data)
    }
}

extension LoopbackCaptureService {
    static let backendSampleRate = 16_000.0

    static func pcmS16Mono16kChunk(from pcmBuffer: AVAudioPCMBuffer) -> Data? {
        let inputSampleRate = pcmBuffer.format.sampleRate
        let frameLength = Int(pcmBuffer.frameLength)

        guard inputSampleRate > 0, frameLength > 0 else {
            return nil
        }

        let monoSamples: [Float]

        switch pcmBuffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = pcmBuffer.floatChannelData else {
                return nil
            }
            monoSamples = monoFloatSamples(from: channelData, channelCount: Int(pcmBuffer.format.channelCount), frameLength: frameLength)
        case .pcmFormatInt16:
            guard let channelData = pcmBuffer.int16ChannelData else {
                return nil
            }
            monoSamples = monoFloatSamples(from: channelData, channelCount: Int(pcmBuffer.format.channelCount), frameLength: frameLength)
        default:
            return nil
        }

        guard monoSamples.isEmpty == false else {
            return nil
        }

        let outputSamples = resample(monoSamples, from: inputSampleRate, to: backendSampleRate)
        guard outputSamples.isEmpty == false else {
            return nil
        }

        return int16LittleEndianData(from: outputSamples)
    }

    private static func monoFloatSamples(
        from channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameLength: Int
    ) -> [Float] {
        guard channelCount > 0, frameLength > 0 else {
            return []
        }

        var samples = Array(repeating: Float.zero, count: frameLength)
        for channel in 0..<channelCount {
            let channelSamples = channelData[channel]
            for frame in 0..<frameLength {
                samples[frame] += channelSamples[frame]
            }
        }

        let divisor = Float(channelCount)
        for frame in 0..<frameLength {
            samples[frame] /= divisor
        }
        return samples
    }

    private static func monoFloatSamples(
        from channelData: UnsafePointer<UnsafeMutablePointer<Int16>>,
        channelCount: Int,
        frameLength: Int
    ) -> [Float] {
        guard channelCount > 0, frameLength > 0 else {
            return []
        }

        var samples = Array(repeating: Float.zero, count: frameLength)
        for channel in 0..<channelCount {
            let channelSamples = channelData[channel]
            for frame in 0..<frameLength {
                samples[frame] += Float(channelSamples[frame]) / 32768.0
            }
        }

        let divisor = Float(channelCount)
        for frame in 0..<frameLength {
            samples[frame] /= divisor
        }
        return samples
    }

    private static func resample(_ samples: [Float], from inputSampleRate: Double, to outputSampleRate: Double) -> [Float] {
        if inputSampleRate == outputSampleRate {
            return samples
        }

        let outputCount = max(1, Int(Double(samples.count) * outputSampleRate / inputSampleRate))
        var output = Array(repeating: Float.zero, count: outputCount)

        for index in 0..<outputCount {
            let sourcePosition = Double(index) * inputSampleRate / outputSampleRate
            let lowerIndex = min(Int(sourcePosition), samples.count - 1)
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(lowerIndex))
            output[index] = samples[lowerIndex] + (samples[upperIndex] - samples[lowerIndex]) * fraction
        }

        return output
    }

    private static func int16LittleEndianData(from samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let clipped = min(max(sample, -1.0), 1.0)
            var value = Int16(clipped * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        return data
    }
}

private extension LoopbackCaptureService {
    enum LoopbackCaptureError: LocalizedError {
        case deviceNotFound
        case cannotAddInput
        case cannotAddOutput

        var errorDescription: String? {
            switch self {
            case .deviceNotFound:
                return "No loopback capture device was found."
            case .cannotAddInput:
                return "The loopback capture input could not be added."
            case .cannotAddOutput:
                return "The loopback capture output could not be added."
            }
        }
    }

    final class SampleBufferDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
        private let handler: (CMSampleBuffer) -> Void

        init(handler: @escaping (CMSampleBuffer) -> Void) {
            self.handler = handler
        }

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            handler(sampleBuffer)
        }
    }

    func resolvedDevice() throws -> AVCaptureDevice {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        if let deviceID,
           let matchedDevice = discoverySession.devices.first(where: { $0.uniqueID == deviceID }) {
            return matchedDevice
        }

        guard let fallbackDevice = discoverySession.devices.first else {
            throw LoopbackCaptureError.deviceNotFound
        }

        return fallbackDevice
    }

    func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        if let snapshot = Self.levelSnapshot(from: sampleBuffer) {
            publish(level: snapshot)
        }

        if let chunk = Self.pcmChunk(from: sampleBuffer) {
            onPCMChunk?(chunk)
        }
    }

    func publish(level: AudioLevelSnapshot) {
        currentLevel = level
        onLevelUpdate?(level)
    }

    static func makeLevelSnapshot(average: Float, peak: Float) -> AudioLevelSnapshot {
        AudioLevelSnapshot(
            averagePower: average,
            peakPower: peak,
            detectedSound: peak > -20 || average > -24
        )
    }

    static func levelSnapshot(from sampleBuffer: CMSampleBuffer) -> AudioLevelSnapshot? {
        guard let pcmBuffer = pcmBuffer(from: sampleBuffer) else {
            return nil
        }

        let format = pcmBuffer.format

        switch format.commonFormat {
        case .pcmFormatFloat32:
            return snapshotFromFloat32Buffer(pcmBuffer)
        case .pcmFormatInt16:
            return snapshotFromInt16Buffer(pcmBuffer)
        default:
            return nil
        }
    }

    static func pcmChunk(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let pcmBuffer = pcmBuffer(from: sampleBuffer) else {
            return nil
        }

        return pcmS16Mono16kChunk(from: pcmBuffer)
    }

    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        let format = AVAudioFormat(streamDescription: streamDescription)
        let frameCount = UInt32(CMSampleBufferGetNumSamples(sampleBuffer))

        guard let format,
              frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        pcmBuffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )

        guard status == noErr else {
            return nil
        }

        return pcmBuffer
    }

    static func snapshotFromFloat32Buffer(_ buffer: AVAudioPCMBuffer) -> AudioLevelSnapshot? {
        guard let channelData = buffer.floatChannelData else {
            return nil
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        guard channelCount > 0, frameLength > 0 else {
            return nil
        }

        var sum: Float = 0
        var peak: Float = 0
        let sampleCount = channelCount * frameLength

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let amplitude = abs(samples[frame])
                sum += amplitude * amplitude
                peak = max(peak, amplitude)
            }
        }

        let rms = sqrt(sum / Float(sampleCount))
        let averagePower = 20 * log10(max(rms, 0.000_000_1))
        let peakPower = 20 * log10(max(peak, 0.000_000_1))
        return makeLevelSnapshot(average: averagePower, peak: peakPower)
    }

    static func snapshotFromInt16Buffer(_ buffer: AVAudioPCMBuffer) -> AudioLevelSnapshot? {
        guard let channelData = buffer.int16ChannelData else {
            return nil
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        guard channelCount > 0, frameLength > 0 else {
            return nil
        }

        var sum: Float = 0
        var peak: Float = 0
        let sampleCount = channelCount * frameLength

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let amplitude = Float(abs(Int(samples[frame])))/Float(Int16.max)
                sum += amplitude * amplitude
                peak = max(peak, amplitude)
            }
        }

        let rms = sqrt(sum / Float(sampleCount))
        let averagePower = 20 * log10(max(rms, 0.000_000_1))
        let peakPower = 20 * log10(max(peak, 0.000_000_1))
        return makeLevelSnapshot(average: averagePower, peak: peakPower)
    }
}
