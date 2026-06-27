# Ohh Lens Live Streaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stream live PCM audio from the macOS app into the local FunASR backend, show partial/final subtitles in real time, save finalized transcript sessions to History, and surface backend disconnect/recovery state clearly.

**Architecture:** Extend `LoopbackCaptureService` with a raw-audio callback, add a dedicated `FunASRStreamingClient` for the WebSocket protocol, and keep product behavior in `AppStore`. `LiveView` remains a thin renderer over state that `AppStore` owns, while tests cover capture conversion seams, protocol event mapping, and session persistence.

**Tech Stack:** Swift 6, SwiftPM, AVFoundation, URLSessionWebSocketTask, SwiftUI, XCTest, FastAPI backend protocol

---

## File Structure

**Create**
- `Sources/OhhLensCore/Models/LiveTranscriptState.swift`
- `Sources/OhhLensCore/Services/FunASRStreamingClient.swift`
- `Tests/OhhLensCoreTests/FunASRStreamingClientTests.swift`

**Modify**
- `Sources/OhhLensCore/Services/FunASRClient.swift`
- `Sources/OhhLensCore/Services/Capture/LoopbackCaptureService.swift`
- `Sources/OhhLensCore/Stores/AppStore.swift`
- `Sources/OhhLensApp/Views/LiveView.swift`
- `Tests/OhhLensCoreTests/AppStoreTests.swift`
- `Tests/OhhLensCoreTests/LoopbackCaptureServiceTests.swift`

---

### Task 1: Add Stream State and App-Facing Service Protocols

**Files:**
- Create: `Sources/OhhLensCore/Models/LiveTranscriptState.swift`
- Modify: `Sources/OhhLensCore/Services/FunASRClient.swift`
- Test: `Tests/OhhLensCoreTests/AppStoreTests.swift`

- [ ] **Step 1: Write the failing `AppStore` test for new live transcript defaults**

```swift
@MainActor
func test_liveTranscriptState_defaultsToIdleAndEmptyTranscript() {
    let store = AppStore()

    XCTAssertEqual(store.liveTranscriptState.phase, .idle)
    XCTAssertEqual(store.liveTranscriptState.partialText, "")
    XCTAssertEqual(store.liveTranscriptState.finalText, "")
    XCTAssertNil(store.liveTranscriptState.lastError)
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
HOME=/Users/steve/dev/personal/ohh-lens/.home \
CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --filter AppStoreTests/test_liveTranscriptState_defaultsToIdleAndEmptyTranscript -v
```

Expected: FAIL because `liveTranscriptState` does not exist yet.

- [ ] **Step 3: Add the minimal state model and protocol surface**

Create `Sources/OhhLensCore/Models/LiveTranscriptState.swift`:

```swift
import Foundation

public struct LiveTranscriptState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case connecting
        case streaming
        case degraded
        case stopping
    }

    public var phase: Phase
    public var partialText: String
    public var finalText: String
    public var lastError: String?

    public init(
        phase: Phase = .idle,
        partialText: String = "",
        finalText: String = "",
        lastError: String? = nil
    ) {
        self.phase = phase
        self.partialText = partialText
        self.finalText = finalText
        self.lastError = lastError
    }
}
```

Update `Sources/OhhLensCore/Services/FunASRClient.swift`:

```swift
import Foundation

public protocol FunASRServicing: Sendable {
    func healthCheck() async -> Bool
}

public enum FunASRStreamingEvent: Equatable, Sendable {
    case ready
    case partial(String)
    case final(String)
    case error(String)
    case closed
}

public protocol FunASRStreamingServicing: Sendable {
    func startSession(language: String) async throws
    func sendAudioChunk(_ data: Data) async throws
    func stopSession() async
    func nextEvent() async throws -> FunASRStreamingEvent
}
```

Update `AppStore` stored properties near the top of `Sources/OhhLensCore/Stores/AppStore.swift`:

```swift
public var liveTranscriptState = LiveTranscriptState()
```

- [ ] **Step 4: Run the focused test to verify it passes**

Run:

```bash
HOME=/Users/steve/dev/personal/ohh-lens/.home \
CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --filter AppStoreTests/test_liveTranscriptState_defaultsToIdleAndEmptyTranscript -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/OhhLensCore/Models/LiveTranscriptState.swift Sources/OhhLensCore/Services/FunASRClient.swift Sources/OhhLensCore/Stores/AppStore.swift Tests/OhhLensCoreTests/AppStoreTests.swift
git commit -m "feat: add live transcript state model"
```

### Task 2: Extend Loopback Capture to Emit PCM Chunks

**Files:**
- Modify: `Sources/OhhLensCore/Services/Capture/LoopbackCaptureService.swift`
- Test: `Tests/OhhLensCoreTests/LoopbackCaptureServiceTests.swift`

- [ ] **Step 1: Write the failing capture conversion test**

Add to `Tests/OhhLensCoreTests/LoopbackCaptureServiceTests.swift`:

```swift
func test_testDoublePublishesPCMChunks() {
    let service = LoopbackCaptureService.testDouble(source: .systemAudio)
    var receivedChunks: [Data] = []

    service.onPCMChunk = { chunk in
        receivedChunks.append(chunk)
    }

    service.receiveTestPCMChunk(Data([0x01, 0x02, 0x03, 0x04]))

    XCTAssertEqual(receivedChunks, [Data([0x01, 0x02, 0x03, 0x04])])
}
```

- [ ] **Step 2: Run the focused capture test to verify it fails**

Run:

```bash
HOME=/Users/steve/dev/personal/ohh-lens/.home \
CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --filter LoopbackCaptureServiceTests/test_testDoublePublishesPCMChunks -v
```

Expected: FAIL because `onPCMChunk` or `receiveTestPCMChunk` does not exist.

- [ ] **Step 3: Add the raw-audio callback seam and publish path**

In `Sources/OhhLensCore/Services/Capture/LoopbackCaptureService.swift`, add a callback near `onLevelUpdate`:

```swift
public var onPCMChunk: (@Sendable (Data) -> Void)?
```

Add a test helper near `receiveTestPower`:

```swift
func receiveTestPCMChunk(_ data: Data) {
    onPCMChunk?(data)
}
```

Split `handleSampleBuffer(_:)` so it publishes both level and raw audio:

```swift
func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    if let snapshot = Self.levelSnapshot(from: sampleBuffer) {
        publish(level: snapshot)
    }

    if let chunk = Self.pcmChunk(from: sampleBuffer) {
        onPCMChunk?(chunk)
    }
}
```

Add a focused conversion helper:

```swift
static func pcmChunk(from sampleBuffer: CMSampleBuffer) -> Data? {
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

    switch format.commonFormat {
    case .pcmFormatInt16:
        return int16Chunk(from: pcmBuffer)
    case .pcmFormatFloat32:
        return int16ChunkFromFloat32(from: pcmBuffer)
    default:
        return nil
    }
}
```

- [ ] **Step 4: Run the focused capture test to verify it passes**

Run:

```bash
HOME=/Users/steve/dev/personal/ohh-lens/.home \
CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --filter LoopbackCaptureServiceTests/test_testDoublePublishesPCMChunks -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/OhhLensCore/Services/Capture/LoopbackCaptureService.swift Tests/OhhLensCoreTests/LoopbackCaptureServiceTests.swift
git commit -m "feat: emit pcm chunks from loopback capture"
```

### Task 3: Implement the FunASR WebSocket Streaming Client

**Files:**
- Create: `Sources/OhhLensCore/Services/FunASRStreamingClient.swift`
- Test: `Tests/OhhLensCoreTests/FunASRStreamingClientTests.swift`

- [ ] **Step 1: Write the failing protocol event mapping test**

Create `Tests/OhhLensCoreTests/FunASRStreamingClientTests.swift`:

```swift
import XCTest
@testable import OhhLensCore

final class FunASRStreamingClientTests: XCTestCase {
    func test_mapsPartialEventPayload() throws {
        let event = try FunASRStreamingClient.decodeEvent(
            from: #"{"type":"partial","text":"hello world"}"#.data(using: .utf8)!
        )

        XCTAssertEqual(event, .partial("hello world"))
    }
}
```

- [ ] **Step 2: Run the focused streaming client test to verify it fails**

Run:

```bash
HOME=/Users/steve/dev/personal/ohh-lens/.home \
CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --filter FunASRStreamingClientTests/test_mapsPartialEventPayload -v
```

Expected: FAIL because `FunASRStreamingClient` does not exist.

- [ ] **Step 3: Add the minimal streaming client**

Create `Sources/OhhLensCore/Services/FunASRStreamingClient.swift`:

```swift
import Foundation

public actor FunASRStreamingClient: FunASRStreamingServicing {
    private let webSocketURL: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    public init(
        webSocketURL: URL = URL(string: "ws://127.0.0.1:8765/ws/transcribe")!,
        session: URLSession = .shared
    ) {
        self.webSocketURL = webSocketURL
        self.session = session
    }

    public func startSession(language: String) async throws {
        let task = session.webSocketTask(with: webSocketURL)
        self.task = task
        task.resume()

        let payload = StartMessage(
            type: "start",
            sessionID: UUID().uuidString,
            sampleRate: 16_000,
            channels: 1,
            sampleFormat: "pcm_s16le",
            language: language
        )

        let data = try JSONEncoder().encode(payload)
        try await task.send(.data(data))
    }

    public func sendAudioChunk(_ data: Data) async throws {
        try await task?.send(.data(data))
    }

    public func stopSession() async {
        guard let task else { return }
        let payload = #"{"type":"stop"}"#
        try? await task.send(.string(payload))
        task.cancel(with: .goingAway, reason: nil)
        self.task = nil
    }

    public func nextEvent() async throws -> FunASRStreamingEvent {
        guard let task else { throw StreamingError.notConnected }
        let message = try await task.receive()

        switch message {
        case .string(let string):
            return try Self.decodeEvent(from: Data(string.utf8))
        case .data(let data):
            return try Self.decodeEvent(from: data)
        @unknown default:
            throw StreamingError.unsupportedMessage
        }
    }

    static func decodeEvent(from data: Data) throws -> FunASRStreamingEvent {
        let payload = try JSONDecoder().decode(EventPayload.self, from: data)

        switch payload.type {
        case "ready":
            return .ready
        case "partial":
            return .partial(payload.text ?? "")
        case "final":
            return .final(payload.text ?? "")
        case "error":
            return .error(payload.message ?? payload.text ?? "Unknown backend error")
        case "closed":
            return .closed
        default:
            throw StreamingError.unknownEvent(payload.type)
        }
    }
}
```

- [ ] **Step 4: Run the focused streaming client test to verify it passes**

Run:

```bash
HOME=/Users/steve/dev/personal/ohh-lens/.home \
CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --filter FunASRStreamingClientTests/test_mapsPartialEventPayload -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/OhhLensCore/Services/FunASRStreamingClient.swift Tests/OhhLensCoreTests/FunASRStreamingClientTests.swift
git commit -m "feat: add websocket streaming client"
```

### Task 4: Wire AppStore Session Lifecycle, History Persistence, and UI

**Files:**
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`
- Modify: `Sources/OhhLensApp/Views/LiveView.swift`
- Modify: `Tests/OhhLensCoreTests/AppStoreTests.swift`

- [ ] **Step 1: Write the failing AppStore persistence test**

Add to `Tests/OhhLensCoreTests/AppStoreTests.swift`:

```swift
@MainActor
func test_stopListening_persistsFinalTranscriptToHistory() async {
    let historyStore = InMemoryHistoryStore()
    let captureService = LoopbackCaptureService.testDouble(source: .systemAudio)
    let streamingClient = StubStreamingClient(
        events: [.ready, .partial("hel"), .final("hello world"), .closed]
    )

    let store = AppStore(
        historyStore: historyStore,
        loopbackCaptureServiceFactory: { _, _ in captureService },
        streamingClientFactory: { streamingClient }
    )

    store.selectedSource = .systemAudio
    store.selectedLoopbackDeviceID = "blackhole"
    store.startListening()
    captureService.receiveTestPCMChunk(Data([0x00, 0x01]))

    await Task.yield()
    store.stopListening()

    XCTAssertEqual(store.history.count, 1)
    XCTAssertEqual(store.history[0].segments.first?.originalText, "hello world")
}
```

- [ ] **Step 2: Run the focused AppStore test to verify it fails**

Run:

```bash
HOME=/Users/steve/dev/personal/ohh-lens/.home \
CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --filter AppStoreTests/test_stopListening_persistsFinalTranscriptToHistory -v
```

Expected: FAIL because `AppStore` does not manage the streaming lifecycle yet.

- [ ] **Step 3: Add the AppStore streaming session wiring**

Update `Sources/OhhLensCore/Stores/AppStore.swift` so it owns:

```swift
private let streamingClientFactory: () -> FunASRStreamingServicing
private var streamingTask: Task<Void, Never>?
private var streamingClient: FunASRStreamingServicing?
private var currentSession = AudioChunkPipeline().beginSession(
    source: .systemAudio,
    languages: LanguagePair(source: "auto", target: "en")
)
```

Inside `startListening()` for loopback sources:

```swift
liveTranscriptState = LiveTranscriptState(phase: .connecting)
backendStatusText = "Connecting to local FunASR backend"

let client = streamingClientFactory()
streamingClient = client

streamingTask = Task { [weak self] in
    guard let self else { return }

    do {
        try await client.startSession(language: self.languagePair.source)
        await self.consumeStreamingEvents(from: client)
    } catch {
        await MainActor.run {
            self.liveTranscriptState.phase = .degraded
            self.liveTranscriptState.lastError = error.localizedDescription
            self.backendStatusText = "Streaming failed"
            self.stopListening()
        }
    }
}

service.onPCMChunk = { [weak self] chunk in
    guard let self else { return }
    Task {
        try? await self.streamingClient?.sendAudioChunk(chunk)
    }
}
```

Add event handling helpers in `AppStore`:

```swift
private func handleStreamingEvent(_ event: FunASRStreamingEvent) {
    switch event {
    case .ready:
        liveTranscriptState.phase = .streaming
        backendStatusText = "Backend streaming"
    case .partial(let text):
        liveTranscriptState.partialText = text
        statusText = "Receiving partial subtitles"
    case .final(let text):
        liveTranscriptState.partialText = ""
        liveTranscriptState.finalText = text
        let updatedSession = AudioChunkPipeline().appendSegment(
            transcript: text,
            translation: nil,
            to: currentSession
        )
        currentSession = updatedSession
    case .error(let message):
        liveTranscriptState.phase = .degraded
        liveTranscriptState.lastError = message
        backendStatusText = "Backend error"
    case .closed:
        backendStatusText = "Backend closed"
    }
}
```

Update `stopListening()` to:

```swift
liveTranscriptState.phase = .stopping
streamingTask?.cancel()
streamingTask = nil

Task {
    await streamingClient?.stopSession()
}

if currentSession.segments.isEmpty == false {
    appendHistorySession(currentSession)
}

currentSession = AudioChunkPipeline().beginSession(
    source: selectedSource,
    languages: languagePair
)
liveTranscriptState = LiveTranscriptState()
```

Update `Sources/OhhLensApp/Views/LiveView.swift` to show:

```swift
if appStore.liveTranscriptState.partialText.isEmpty == false {
    Text(appStore.liveTranscriptState.partialText)
        .font(.title3.monospaced())
}

if appStore.liveTranscriptState.finalText.isEmpty == false {
    Text(appStore.liveTranscriptState.finalText)
        .font(.body)
}

if let lastError = appStore.liveTranscriptState.lastError {
    Text(lastError)
        .foregroundStyle(.red)
}
```

- [ ] **Step 4: Run focused AppStore tests, then the full suite**

Run:

```bash
HOME=/Users/steve/dev/personal/ohh-lens/.home \
CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --filter AppStoreTests/test_stopListening_persistsFinalTranscriptToHistory -v
```

Then:

```bash
HOME=/Users/steve/dev/personal/ohh-lens/.home \
CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test -v
```

Expected: focused test PASS, then full test suite PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/OhhLensCore/Stores/AppStore.swift Sources/OhhLensApp/Views/LiveView.swift Tests/OhhLensCoreTests/AppStoreTests.swift
git commit -m "feat: wire live subtitle streaming into app state"
```
