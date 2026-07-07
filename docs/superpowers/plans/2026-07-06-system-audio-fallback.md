# System Audio Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `System Audio` start live transcription even when no loopback device is installed by falling back to microphone capture, while keeping the UI honest about the active path.

**Architecture:** Keep fallback policy in `AppStore`, not in the capture services. Add a focused `EffectiveCaptureMode` model plus session metadata for the resolved path, then drive header, setup, and idle copy from derived store state rather than scattering availability checks across views.

**Tech Stack:** Swift, SwiftUI, Observation, XCTest, existing `AudioCaptureServicing`/`FunASRStreamingServicing` infrastructure

---

## File Structure

- Create: `Sources/OhhLensCore/Models/EffectiveCaptureMode.swift`
  Owns the derived capture-path state used by store logic and UI copy.
- Modify: `Sources/OhhLensCore/Models/SessionRecord.swift`
  Stores the resolved capture mode alongside the user-selected source for history/debugging.
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`
  Resolves fallback behavior, updates setup/status messaging, and writes session metadata.
- Modify: `Sources/OhhLensApp/Views/Shared/TranscriptWidgets.swift`
  Renders the live-header pill and idle message from derived capture mode instead of raw loopback availability alone.
- Modify: `Sources/OhhLensApp/Views/SetupView.swift`
  Reframes loopback copy as a capability enhancer and explains `System Audio` fallback versus `App Audio` requirements.
- Modify: `Tests/OhhLensCoreTests/AppStoreTests.swift`
  Covers fallback resolution, blocked `App Audio`, setup/status text, and session metadata.

### Task 1: Lock Store-Level Fallback Behavior With Tests

**Files:**
- Modify: `Tests/OhhLensCoreTests/AppStoreTests.swift`
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`
- Modify: `Sources/OhhLensCore/Models/SessionRecord.swift`

- [ ] **Step 1: Add a failing test for `System Audio` fallback selection**

```swift
@MainActor
func test_systemAudioWithoutLoopbackFallsBackToMicrophoneCapture() {
    let captureService = TestAudioCaptureService(source: .microphone)
    var requestedSource: AudioSource?
    var requestedDeviceID: String?

    let store = AppStore(
        historyStore: nil,
        deviceCatalog: .init(),
        audioCaptureServiceFactory: { source, deviceID in
            requestedSource = source
            requestedDeviceID = deviceID
            return captureService
        },
        streamingClientFactory: { StubStreamingClient(events: [.ready]) }
    )

    store.selectedSource = .systemAudio
    store.selectedLoopbackDeviceID = nil
    store.startListening()

    XCTAssertEqual(requestedSource, .microphone)
    XCTAssertNil(requestedDeviceID)
    XCTAssertEqual(store.effectiveCaptureMode, .systemAudioFallbackMicrophone)
}
```

- [ ] **Step 2: Run the targeted test and verify it fails**

Run:

```bash
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppStoreTests/test_systemAudioWithoutLoopbackFallsBackToMicrophoneCapture -v'
```

Expected: FAIL because `AppStore` still blocks when `selectedLoopbackDeviceID` is missing and `effectiveCaptureMode` does not exist.

- [ ] **Step 3: Add failing tests for blocked `App Audio` and session metadata**

```swift
@MainActor
func test_appAudioWithoutLoopbackStaysBlocked() {
    var factoryCallCount = 0
    let store = AppStore(
        historyStore: nil,
        deviceCatalog: .init(),
        audioCaptureServiceFactory: { _, _ in
            factoryCallCount += 1
            return TestAudioCaptureService(source: .appAudio)
        },
        streamingClientFactory: { StubStreamingClient(events: [.ready]) }
    )

    store.selectedSource = .appAudio
    store.selectedLoopbackDeviceID = nil
    store.startListening()

    XCTAssertEqual(factoryCallCount, 0)
    XCTAssertFalse(store.isListening)
    XCTAssertEqual(store.effectiveCaptureMode, .appAudioRequiresLoopback)
    XCTAssertEqual(store.statusText, "App Audio requires loopback")
}

@MainActor
func test_fallbackSessionRecordsIntendedSourceAndEffectiveCaptureMode() async {
    let historyStore = HistoryStore(
        baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    )
    let captureService = TestAudioCaptureService(source: .microphone)
    let streamingClient = StubStreamingClient(events: [.ready, .final("hello"), .closed])

    let store = AppStore(
        historyStore: historyStore,
        deviceCatalog: .init(),
        audioCaptureServiceFactory: { _, _ in captureService },
        streamingClientFactory: { streamingClient }
    )

    store.selectedSource = .systemAudio
    store.startListening()

    for _ in 0..<20 where store.history.isEmpty {
        await Task.yield()
    }

    XCTAssertEqual(store.history.first?.source, .systemAudio)
    XCTAssertEqual(store.history.first?.effectiveCaptureMode, .systemAudioFallbackMicrophone)
}
```

- [ ] **Step 4: Run the targeted AppStore suite and verify the new cases fail**

Run:

```bash
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppStoreTests -v'
```

Expected: Existing tests pass; the new fallback-specific cases fail on missing types/messages/metadata.

- [ ] **Step 5: Commit the red test scaffolding**

```bash
git add Tests/OhhLensCoreTests/AppStoreTests.swift
git commit -m "test: cover system audio fallback rules"
```

### Task 2: Implement `effectiveCaptureMode` And Fallback Resolution

**Files:**
- Create: `Sources/OhhLensCore/Models/EffectiveCaptureMode.swift`
- Modify: `Sources/OhhLensCore/Models/SessionRecord.swift`
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`
- Test: `Tests/OhhLensCoreTests/AppStoreTests.swift`

- [ ] **Step 1: Add the new capture-mode model**

```swift
import Foundation

public enum EffectiveCaptureMode: String, Codable, Equatable {
    case microphone
    case routedSystemAudio
    case systemAudioFallbackMicrophone
    case appAudio
    case appAudioRequiresLoopback

    public var statusLabel: String {
        switch self {
        case .microphone:
            "Microphone"
        case .routedSystemAudio:
            "Loopback Device"
        case .systemAudioFallbackMicrophone:
            "Live Audio"
        case .appAudio:
            "App Audio"
        case .appAudioRequiresLoopback:
            "App Audio Unavailable"
        }
    }
}
```

- [ ] **Step 2: Extend `SessionRecord` to persist the resolved mode**

```swift
public struct SessionRecord: Equatable, Codable, Identifiable {
    public let id: UUID
    public var source: AudioSource
    public var effectiveCaptureMode: EffectiveCaptureMode?
    public var languages: LanguagePair
    public var createdAt: Date
    public var segments: [TranscriptSegment]

    public init(
        id: UUID = UUID(),
        source: AudioSource,
        effectiveCaptureMode: EffectiveCaptureMode? = nil,
        languages: LanguagePair,
        createdAt: Date = .now,
        segments: [TranscriptSegment] = []
    ) {
        self.id = id
        self.source = source
        self.effectiveCaptureMode = effectiveCaptureMode
        self.languages = languages
        self.createdAt = createdAt
        self.segments = segments
    }
}
```

- [ ] **Step 3: Refactor `AppStore` to resolve the effective path before starting capture**

```swift
public var effectiveCaptureMode: EffectiveCaptureMode {
    if isListening, let activeCaptureMode {
        return activeCaptureMode
    }

    switch selectedSource {
    case .microphone:
        return .microphone
    case .systemAudio:
        return selectedLoopbackDeviceID == nil ? .systemAudioFallbackMicrophone : .routedSystemAudio
    case .appAudio:
        return selectedLoopbackDeviceID == nil ? .appAudioRequiresLoopback : .appAudio
    case .importedFile:
        return .microphone
    }
}

private var activeCaptureMode: EffectiveCaptureMode?

private func resolveCaptureRequest() -> (source: AudioSource, deviceID: String?, mode: EffectiveCaptureMode)? {
    switch selectedSource {
    case .microphone:
        return (.microphone, nil, .microphone)
    case .systemAudio:
        if let deviceID = selectedLoopbackDeviceID {
            return (.systemAudio, deviceID, .routedSystemAudio)
        }
        return (.microphone, nil, .systemAudioFallbackMicrophone)
    case .appAudio:
        guard let deviceID = selectedLoopbackDeviceID else {
            statusText = "App Audio requires loopback"
            updateSetupMessage("Install a virtual audio device to isolate audio from a single app.")
            activeCaptureMode = .appAudioRequiresLoopback
            isListening = false
            return nil
        }
        return (.appAudio, deviceID, .appAudio)
    case .importedFile:
        return nil
    }
}
```

- [ ] **Step 4: Wire the resolved mode into session creation and startup messages**

```swift
guard let request = resolveCaptureRequest() else {
    return
}

var service = audioCaptureServiceFactory(request.source, request.deviceID)

try service.start()
activeCaptureMode = request.mode
currentSession = audioChunkPipeline.beginSession(source: selectedSource, languages: languagePair)
currentSession?.effectiveCaptureMode = request.mode
statusText = request.mode == .systemAudioFallbackMicrophone ? "Listening with Live Audio" : "Listening for audio"
backendStatusText = "Connecting to local FunASR backend"
```

- [ ] **Step 5: Run AppStore tests, then commit the fallback implementation**

Run:

```bash
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppStoreTests -v'
```

Expected: PASS for the new fallback-resolution tests and existing store tests.

```bash
git add Sources/OhhLensCore/Models/EffectiveCaptureMode.swift Sources/OhhLensCore/Models/SessionRecord.swift Sources/OhhLensCore/Stores/AppStore.swift Tests/OhhLensCoreTests/AppStoreTests.swift
git commit -m "feat: add system audio fallback resolution"
```

### Task 3: Make Header And Idle Copy Source-Aware

**Files:**
- Modify: `Sources/OhhLensApp/Views/Shared/TranscriptWidgets.swift`
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`
- Test: `Tests/OhhLensCoreTests/AppStoreTests.swift`

- [ ] **Step 1: Add a failing store test for fallback-facing copy**

```swift
@MainActor
func test_systemAudioFallbackUsesLiveAudioMessaging() {
    let store = AppStore(
        historyStore: nil,
        deviceCatalog: .init(),
        audioCaptureServiceFactory: { _, _ in TestAudioCaptureService(source: .microphone) },
        streamingClientFactory: { StubStreamingClient(events: [.ready]) }
    )

    store.selectedSource = .systemAudio

    XCTAssertEqual(store.effectiveCaptureMode.statusLabel, "Live Audio")
    XCTAssertEqual(store.liveIdleMessage, "Press Start Listening to capture live audio through your microphone.")
}
```

- [ ] **Step 2: Run the targeted copy test and verify it fails**

Run:

```bash
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppStoreTests/test_systemAudioFallbackUsesLiveAudioMessaging -v'
```

Expected: FAIL because `liveIdleMessage` and fallback-aware labels do not exist yet.

- [ ] **Step 3: Add derived UI text helpers in `AppStore` and use them in `TranscriptWidgets`**

```swift
public var liveIdleMessage: String {
    switch effectiveCaptureMode {
    case .microphone:
        "Press Start Listening to capture live speech from your microphone."
    case .routedSystemAudio:
        "Press Start Listening to capture routed system audio in real time."
    case .systemAudioFallbackMicrophone:
        "Press Start Listening to capture live audio through your microphone."
    case .appAudio:
        "Press Start Listening to capture routed audio from the selected app."
    case .appAudioRequiresLoopback:
        "Install a virtual audio device before starting App Audio capture."
    }
}
```

```swift
struct TranscriptScreenHeader: View {
    let title: String
    let effectiveCaptureMode: EffectiveCaptureMode
    let selectedSource: AudioSource
    let isListening: Bool
    let isPiPVisible: Bool
    let availableLoopbackDevices: [AudioInputDevice]
    @Binding var selectedLoopbackDeviceID: String?
    let onTogglePiP: () -> Void

    @ViewBuilder
    private var headerMiddleControl: some View {
        switch effectiveCaptureMode {
        case .routedSystemAudio, .appAudio:
            CompactSelectionField(
                title: "Loopback Device",
                selection: Binding(
                    get: { selectedLoopbackDeviceID ?? "" },
                    set: { selectedLoopbackDeviceID = $0 }
                ),
                options: availableLoopbackDevices.map(\.id),
                label: loopbackName(for:)
            )
        case .systemAudioFallbackMicrophone:
            MissingLoopbackPill(text: isListening ? "Live Audio" : "Live Audio Ready")
        case .appAudioRequiresLoopback:
            MissingLoopbackPill(text: "App Audio Needs Loopback")
        case .microphone:
            MissingLoopbackPill(text: isListening ? "Microphone Live" : "Microphone Ready")
        }
    }
}
```

- [ ] **Step 4: Update `LiveView` and `ConversationsView` call sites to pass `effectiveCaptureMode`, then rerun tests**

Run:

```bash
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppStoreTests -v'
```

Expected: PASS with the new fallback-copy expectations.

- [ ] **Step 5: Commit the live-surface messaging update**

```bash
git add Sources/OhhLensCore/Stores/AppStore.swift Sources/OhhLensApp/Views/Shared/TranscriptWidgets.swift Sources/OhhLensApp/Views/LiveView.swift Sources/OhhLensApp/Views/ConversationsView.swift Tests/OhhLensCoreTests/AppStoreTests.swift
git commit -m "feat: surface live audio fallback in live views"
```

### Task 4: Reframe Setup Messaging And Run End-To-End Verification

**Files:**
- Modify: `Sources/OhhLensApp/Views/SetupView.swift`
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`
- Test: `Tests/OhhLensCoreTests/AppStoreTests.swift`

- [ ] **Step 1: Add a failing store test for setup diagnostics without loopback**

```swift
@MainActor
func test_refreshLoopbackDevicesExplainsFallbackAndAppAudioConstraint() {
    let store = AppStore(
        historyStore: nil,
        deviceCatalog: .init(),
        audioCaptureServiceFactory: { _, _ in TestAudioCaptureService(source: .microphone) },
        streamingClientFactory: { StubStreamingClient(events: [.ready]) }
    )

    store.refreshLoopbackDevices()

    XCTAssertEqual(
        store.setupMessage,
        "No virtual audio device found. System Audio will use Live Audio fallback; App Audio still requires loopback."
    )
}
```

- [ ] **Step 2: Run the targeted diagnostic test and verify it fails**

Run:

```bash
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppStoreTests/test_refreshLoopbackDevicesExplainsFallbackAndAppAudioConstraint -v'
```

Expected: FAIL because `refreshLoopbackDevices()` still emits the old “install and route system audio” message.

- [ ] **Step 3: Update `AppStore.refreshLoopbackDevices()` and `SetupView` copy**

```swift
if let firstDevice = devices.first {
    updateSetupMessage("Loopback device ready: \(firstDevice.name). System Audio can use routed capture.")
} else {
    updateSetupMessage("No virtual audio device found. System Audio will use Live Audio fallback; App Audio still requires loopback.")
}
```

```swift
settingsRow(
    title: "Loopback Device",
    detail: "Virtual devices enable true routed System Audio and App Audio capture. Without one, System Audio falls back to Live Audio through the microphone."
) {
    HStack(spacing: 8) {
        Picker(
            "Loopback Device",
            selection: Binding(
                get: { appStore.selectedLoopbackDeviceID ?? "" },
                set: { appStore.selectedLoopbackDeviceID = $0 }
            )
        ) {
            ForEach(appStore.availableLoopbackDevices) { device in
                Text(device.name)
                    .tag(device.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(alignment: .leading)

        Button("Scan System") {
            appStore.refreshLoopbackDevices()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .background(controlBackground)
    }
}
```

- [ ] **Step 4: Run focused tests plus a build for regression coverage**

Run:

```bash
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppStoreTests -v'
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build'
```

Expected: All `AppStoreTests` PASS and the app builds successfully.

- [ ] **Step 5: Commit the setup-screen update and perform a manual smoke pass**

```bash
git add Sources/OhhLensApp/Views/SetupView.swift Sources/OhhLensCore/Stores/AppStore.swift Tests/OhhLensCoreTests/AppStoreTests.swift
git commit -m "feat: explain live audio fallback in setup"
```

Manual smoke checklist:

```text
1. Launch the app with no loopback device installed.
2. Select System Audio in Live Subtitles and confirm the header shows Live Audio.
3. Start listening and confirm the session does not hard-fail.
4. Select App Audio and confirm the app stays blocked with loopback guidance.
5. Open App Settings and confirm the diagnostics/setup copy matches the fallback behavior.
```
