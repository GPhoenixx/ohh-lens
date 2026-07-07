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
    private var activeDeviceName = "Unknown device"
    private var loggedPCMChunkCount = 0

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
        print("device: \(device)")
        activeDeviceName = device.localizedName
        Self.emitConsoleLine("LoopbackCapture start source=\(source.rawValue) device=\(activeDeviceName)")
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
        loggedPCMChunkCount = 0
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

    struct DebugChunkContext {
        let chunkIndex: Int
        let deviceName: String
    }

    static func pcmS16Mono16kChunk(from pcmBuffer: AVAudioPCMBuffer, debugContext: DebugChunkContext? = nil) -> Data? {
        let inputSampleRate = pcmBuffer.format.sampleRate
        let frameLength = Int(pcmBuffer.frameLength)

        guard inputSampleRate > 0, frameLength > 0 else {
            return nil
        }

        let inputSummary = "rate=\(inputSampleRate)Hz channels=\(pcmBuffer.format.channelCount) format=\(String(describing: pcmBuffer.format.commonFormat)) frames=\(frameLength)"
        let monoSamples: [Float]
        let inputPreview: String

        switch pcmBuffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = pcmBuffer.floatChannelData else {
                return nil
            }
            inputPreview = debugFloatChannelPreview(from: channelData, channelCount: Int(pcmBuffer.format.channelCount), frameLength: frameLength)
            monoSamples = monoFloatSamples(from: channelData, channelCount: Int(pcmBuffer.format.channelCount), frameLength: frameLength)
        case .pcmFormatInt16:
            guard let channelData = pcmBuffer.int16ChannelData else {
                return nil
            }
            inputPreview = debugInt16ChannelPreview(from: channelData, channelCount: Int(pcmBuffer.format.channelCount), frameLength: frameLength)
            monoSamples = monoFloatSamples(from: channelData, channelCount: Int(pcmBuffer.format.channelCount), frameLength: frameLength)
        default:
            return nil
        }

        guard monoSamples.isEmpty == false else {
            return nil
        }

        if let debugContext {
            let preview = debugFloatPreview(for: monoSamples)
            logStep(
                5,
                "monoFloatSamples",
                chunkIndex: debugContext.chunkIndex,
                deviceName: debugContext.deviceName,
                message: "input=\(inputSummary) \(inputPreview) output=mono \(preview)"
            )
        }

        let outputSamples = resample(monoSamples, from: inputSampleRate, to: backendSampleRate)
        guard outputSamples.isEmpty == false else {
            return nil
        }

        if let debugContext {
            let preview = debugFloatPreview(for: outputSamples)
            logStep(
                6,
                "resample",
                chunkIndex: debugContext.chunkIndex,
                deviceName: debugContext.deviceName,
                message: "input=\(debugFloatPreview(for: monoSamples)) @\(inputSampleRate)Hz output=\(preview) @\(backendSampleRate)Hz outputCount=\(outputSamples.count)"
            )
        }

        return int16LittleEndianData(from: outputSamples, debugContext: debugContext)
    }

    static func shouldLogPCMChunk(index: Int, source: AudioSource) -> Bool {
        return index <= 5 || index.isMultiple(of: 50)
    }

    static func debugPCMPreview(for chunk: Data, maxSamples: Int = 8) -> String {
        guard maxSamples > 0 else {
            return "[]"
        }

        let samples = chunk.withUnsafeBytes { rawBuffer -> [Int16] in
            guard let baseAddress = rawBuffer.baseAddress else {
                return []
            }

            let sampleCount = min(maxSamples, chunk.count / MemoryLayout<Int16>.size)
            let typedBuffer = baseAddress.assumingMemoryBound(to: Int16.self)

            return (0..<sampleCount).map { index in
                Int16(littleEndian: typedBuffer[index])
            }
        }

        return "[" + samples.map(String.init).joined(separator: ", ") + "]"
    }

    static func debugFloatPreview(for samples: [Float], maxSamples: Int = 8) -> String {
        guard maxSamples > 0 else {
            return "[]"
        }

        let preview = samples.prefix(maxSamples).map { sample in
            String(format: "%.4f", sample)
        }

        return "[" + preview.joined(separator: ", ") + "]"
    }

    static func debugFloatChannelPreview(
        from channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameLength: Int,
        maxSamples: Int = 4
    ) -> String {
        guard channelCount > 0, frameLength > 0, maxSamples > 0 else {
            return "channels=[]"
        }

        let sampleCount = min(frameLength, maxSamples)
        let previews = (0..<channelCount).map { channel -> String in
            let samples = (0..<sampleCount).map { index in
                String(format: "%.4f", channelData[channel][index])
            }
            return "ch\(channel)=[" + samples.joined(separator: ", ") + "]"
        }

        return previews.joined(separator: " ")
    }

    static func debugPCMBufferPreview(_ buffer: AVAudioPCMBuffer, maxSamples: Int = 4) -> String {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData else {
                return "channels=[]"
            }
            return debugFloatChannelPreview(
                from: channelData,
                channelCount: channelCount,
                frameLength: frameLength,
                maxSamples: maxSamples
            )
        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData else {
                return "channels=[]"
            }
            return debugInt16ChannelPreview(
                from: channelData,
                channelCount: channelCount,
                frameLength: frameLength,
                maxSamples: maxSamples
            )
        default:
            return "channels=[]"
        }
    }

    static func debugInt16ChannelPreview(
        from channelData: UnsafePointer<UnsafeMutablePointer<Int16>>,
        channelCount: Int,
        frameLength: Int,
        maxSamples: Int = 4
    ) -> String {
        guard channelCount > 0, frameLength > 0, maxSamples > 0 else {
            return "channels=[]"
        }

        let sampleCount = min(frameLength, maxSamples)
        let previews = (0..<channelCount).map { channel -> String in
            let samples = (0..<sampleCount).map { index in
                String(channelData[channel][index])
            }
            return "ch\(channel)=[" + samples.joined(separator: ", ") + "]"
        }

        return previews.joined(separator: " ")
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

    private static func int16LittleEndianData(from samples: [Float], debugContext: DebugChunkContext? = nil) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        var previewSamples: [Int16] = []
        for sample in samples {
            let clipped = min(max(sample, -1.0), 1.0)
            var value = Int16(clipped * Float(Int16.max)).littleEndian
            if previewSamples.count < 8 {
                previewSamples.append(Int16(littleEndian: value))
            }
            withUnsafeBytes(of: &value) { bytes in
                data.append(contentsOf: bytes)
            }
        }

        if let debugContext {
            let preview = "[" + previewSamples.map(String.init).joined(separator: ", ") + "]"
            logStep(
                7,
                "int16LittleEndianData",
                chunkIndex: debugContext.chunkIndex,
                deviceName: debugContext.deviceName,
                message: "input=\(debugFloatPreview(for: samples)) output=bytes=\(data.count) samples=\(preview)"
            )
        }

        return data
    }

    static func logStep(
        _ step: Int,
        _ functionName: String,
        chunkIndex: Int,
        deviceName: String,
        message: String
    ) {
        emitConsoleLine("BLACKHOLE_DEBUG: [Step \(step)] chunk #\(chunkIndex) \(functionName) device=\(deviceName) \(message)")
    }

    static func emitConsoleLine(_ line: String) {
        print(line)
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

        let catalog = AudioDeviceCatalog(
            devices: discoverySession.devices.map { device in
                AudioInputDevice(id: device.uniqueID, name: device.localizedName, isInput: true)
            }
        )

        if let preferredDeviceID = catalog.preferredInputDevice(for: source)?.id,
           let preferredDevice = discoverySession.devices.first(where: { $0.uniqueID == preferredDeviceID }) {
            return preferredDevice
        }

        guard let fallbackDevice = discoverySession.devices.first else {
            throw LoopbackCaptureError.deviceNotFound
        }

        return fallbackDevice
    }

    func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        loggedPCMChunkCount += 1

        if let debugContext = currentDebugContext {
            Self.logStep(
                1,
                "handleSampleBuffer",
                chunkIndex: debugContext.chunkIndex,
                deviceName: debugContext.deviceName,
                message: "input=CMSampleBuffer source=\(self.source.rawValue) output=begin processing"
            )
        }

        if let snapshot = Self.levelSnapshot(from: sampleBuffer) {
            if let debugContext = currentDebugContext {
                Self.logStep(
                    1,
                    "levelSnapshot",
                    chunkIndex: debugContext.chunkIndex,
                    deviceName: debugContext.deviceName,
                    message: "input=CMSampleBuffer output=average=\(snapshot.averagePower) peak=\(snapshot.peakPower) detectedSound=\(snapshot.detectedSound)"
                )
            }
            publish(level: snapshot)
        }

        if let chunk = Self.pcmChunk(from: sampleBuffer, debugContext: currentDebugContext) {
            logPCMChunkIfNeeded(chunk)
            onPCMChunk?(chunk)
        }
    }

    func logPCMChunkIfNeeded(_ chunk: Data) {
        guard let debugContext = currentDebugContext else {
            return
        }

        Self.logStep(
            8,
            "socket payload",
            chunkIndex: debugContext.chunkIndex,
            deviceName: debugContext.deviceName,
            message: "input=Data bytes=\(chunk.count) samples=\(Self.debugPCMPreview(for: chunk)) output=forward to onPCMChunk/socket"
        )
    }

    var currentDebugContext: DebugChunkContext? {
        guard Self.shouldLogPCMChunk(index: loggedPCMChunkCount, source: source) else {
            return nil
        }

        return DebugChunkContext(chunkIndex: loggedPCMChunkCount, deviceName: activeDeviceName)
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
        pcmChunk(from: sampleBuffer, debugContext: nil)
    }

    static func pcmChunk(from sampleBuffer: CMSampleBuffer, debugContext: DebugChunkContext?) -> Data? {
        if let debugContext {
            logStep(
                2,
                "pcmChunk",
                chunkIndex: debugContext.chunkIndex,
                deviceName: debugContext.deviceName,
                message: "input=CMSampleBuffer output=attempt AVAudioPCMBuffer conversion"
            )
        }

        guard let pcmBuffer = pcmBuffer(from: sampleBuffer) else {
            return nil
        }

        if let debugContext {
            let pcmPreview = debugPCMBufferPreview(pcmBuffer)
            logStep(
                3,
                "pcmBuffer",
                chunkIndex: debugContext.chunkIndex,
                deviceName: debugContext.deviceName,
                message: "input=CMSampleBuffer output=AVAudioPCMBuffer rate=\(pcmBuffer.format.sampleRate)Hz channels=\(pcmBuffer.format.channelCount) format=\(String(describing: pcmBuffer.format.commonFormat)) frames=\(pcmBuffer.frameLength) values=\(pcmPreview)"
            )
            logStep(
                4,
                "pcmS16Mono16kChunk",
                chunkIndex: debugContext.chunkIndex,
                deviceName: debugContext.deviceName,
                message: "input=AVAudioPCMBuffer values=\(pcmPreview) output=target mono/int16/\(backendSampleRate)Hz"
            )
        }

        return pcmS16Mono16kChunk(from: pcmBuffer, debugContext: debugContext)
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
