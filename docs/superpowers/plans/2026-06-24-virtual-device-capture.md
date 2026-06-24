# Virtual Device Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add real virtual-device system audio capture so Ohh Lens can detect and ingest routed YouTube/system audio from a loopback device such as BlackHole.

**Architecture:** Introduce a narrow CoreAudio/AVFoundation-backed loopback device layer inside `OhhLensCore`, then route capture state into `AppStore` so SwiftUI can show device readiness and live audio-flow status. Keep transcription transport out of this slice unless the existing FunASR contract is already sufficient; this slice's definition of done is verified audio flow from a selected virtual device into the app with observable status and chunk callbacks.

**Tech Stack:** Swift 6, AVFoundation, CoreMedia, SwiftUI, Observation, XCTest, SwiftPM

---

## File Structure

- `Sources/OhhLensCore/Models/AudioLevelSnapshot.swift`
  Small value model for capture activity and last observed RMS/peak state.
- `Sources/OhhLensCore/Services/Capture/AudioDeviceCatalog.swift`
  Enumerates available audio capture devices and filters likely virtual/loopback inputs.
- `Sources/OhhLensCore/Services/Capture/LoopbackCaptureService.swift`
  Replaces the placeholder with an `AVCaptureSession`-backed implementation that reads PCM sample buffers from a selected input device and reports audio activity.
- `Sources/OhhLensCore/Stores/AppStore.swift`
  Owns selected loopback device, current audio-flow state, and start/stop orchestration for the loopback capture path.
- `Sources/OhhLensApp/Views/LiveView.swift`
  Adds device selection, flow-status copy, and stronger “audio is flowing / silent / no device” cues.
- `Sources/OhhLensApp/Views/SetupView.swift`
  Adds explicit virtual-device readiness guidance and selected-device diagnostics.
- `Tests/OhhLensCoreTests/LoopbackCaptureServiceTests.swift`
  Covers device filtering and flow-state transitions with test doubles.
- `Tests/OhhLensCoreTests/AppStoreTests.swift`
  Covers store behavior for loopback selection and capture-status updates.

## Task 1: Add Device Discovery Models And Tests

**Files:**
- Create: `Sources/OhhLensCore/Models/AudioLevelSnapshot.swift`
- Create: `Sources/OhhLensCore/Services/Capture/AudioDeviceCatalog.swift`
- Create: `Tests/OhhLensCoreTests/LoopbackCaptureServiceTests.swift`

- [ ] **Step 1: Write the failing tests for virtual-device filtering**

```swift
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
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
swift test --filter LoopbackCaptureServiceTests/test_catalogReturnsLikelyVirtualDevicesFirst -v
```

Expected: FAIL with missing `AudioDeviceCatalog` or `AudioInputDevice`

- [ ] **Step 3: Add the minimal model and catalog implementation**

```swift
// Sources/OhhLensCore/Models/AudioLevelSnapshot.swift
import Foundation

public struct AudioLevelSnapshot: Equatable, Sendable {
    public var averagePower: Float
    public var peakPower: Float
    public var detectedSound: Bool

    public init(averagePower: Float = -160, peakPower: Float = -160, detectedSound: Bool = false) {
        self.averagePower = averagePower
        self.peakPower = peakPower
        self.detectedSound = detectedSound
    }
}
```

```swift
// Sources/OhhLensCore/Services/Capture/AudioDeviceCatalog.swift
import Foundation

public struct AudioInputDevice: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isInput: Bool

    public init(id: String, name: String, isInput: Bool) {
        self.id = id
        self.name = name
        self.isInput = isInput
    }
}

public struct AudioDeviceCatalog {
    private let devices: [AudioInputDevice]

    public init(devices: [AudioInputDevice] = []) {
        self.devices = devices
    }

    public func loopbackInputDevices() -> [AudioInputDevice] {
        devices.filter { device in
            guard device.isInput else { return false }
            let lower = device.name.lowercased()
            return lower.contains("blackhole")
                || lower.contains("vb-cable")
                || lower.contains("loopback")
                || lower.contains("soundflower")
        }
    }
}
```

- [ ] **Step 4: Run the focused test to verify it passes**

Run:

```bash
swift test --filter LoopbackCaptureServiceTests/test_catalogReturnsLikelyVirtualDevicesFirst -v
```

Expected: PASS

- [ ] **Step 5: Commit the discovery slice**

```bash
git add Sources/OhhLensCore/Models/AudioLevelSnapshot.swift Sources/OhhLensCore/Services/Capture/AudioDeviceCatalog.swift Tests/OhhLensCoreTests/LoopbackCaptureServiceTests.swift
git commit -m "feat: add loopback device discovery"
```

## Task 2: Replace The Loopback Capture Placeholder With Real Buffer Capture

**Files:**
- Modify: `Sources/OhhLensCore/Services/Capture/LoopbackCaptureService.swift`
- Modify: `Tests/OhhLensCoreTests/LoopbackCaptureServiceTests.swift`

- [ ] **Step 1: Write a failing test for audio activity updates**

```swift
@MainActor
func test_serviceMarksAudioDetectedWhenSamplePowerExceedsThreshold() {
    let service = LoopbackCaptureService.testDouble(source: .systemAudio)

    service.receiveTestPower(average: -18, peak: -8)

    XCTAssertTrue(service.currentLevel.detectedSound)
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
swift test --filter LoopbackCaptureServiceTests/test_serviceMarksAudioDetectedWhenSamplePowerExceedsThreshold -v
```

Expected: FAIL with missing test helper or `currentLevel`

- [ ] **Step 3: Implement the minimal capture/session layer**

Key implementation requirements:
- Keep `AudioCaptureServicing` source-compatible.
- Add a callback or observable state from `LoopbackCaptureService` for latest `AudioLevelSnapshot`.
- Use `AVCaptureSession`, `AVCaptureDeviceInput`, and `AVCaptureAudioDataOutput`.
- When running in tests, allow direct power injection without touching AVFoundation hardware.

- [ ] **Step 4: Run the focused tests to verify they pass**

Run:

```bash
swift test --filter LoopbackCaptureServiceTests -v
```

Expected: PASS

- [ ] **Step 5: Commit the capture implementation**

```bash
git add Sources/OhhLensCore/Services/Capture/LoopbackCaptureService.swift Tests/OhhLensCoreTests/LoopbackCaptureServiceTests.swift
git commit -m "feat: add loopback audio capture service"
```

## Task 3: Wire Capture State Into AppStore

**Files:**
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`
- Modify: `Tests/OhhLensCoreTests/AppStoreTests.swift`

- [ ] **Step 1: Write the failing store test for system-audio capture state**

```swift
@MainActor
func test_selectingSystemAudioCanExposeDetectedSoundState() {
    let store = AppStore(historyStore: nil)

    store.selectedSource = .systemAudio
    store.updateCaptureLevel(.init(averagePower: -12, peakPower: -6, detectedSound: true))

    XCTAssertTrue(store.captureLevel.detectedSound)
    XCTAssertEqual(store.statusText, "Audio detected")
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
swift test --filter AppStoreTests/test_selectingSystemAudioCanExposeDetectedSoundState -v
```

Expected: FAIL with missing `captureLevel` or `updateCaptureLevel`

- [ ] **Step 3: Add minimal store wiring**

Implementation notes:
- Store `availableLoopbackDevices: [AudioInputDevice]`
- Store `selectedLoopbackDeviceID: String?`
- Store `captureLevel: AudioLevelSnapshot`
- Add `refreshLoopbackDevices()` and `updateCaptureLevel(_:)`
- Only change `statusText` to `"Audio detected"` when system/app audio mode is active and sound is present

- [ ] **Step 4: Run focused tests to verify they pass**

Run:

```bash
swift test --filter AppStoreTests -v
```

Expected: PASS

- [ ] **Step 5: Commit the store slice**

```bash
git add Sources/OhhLensCore/Stores/AppStore.swift Tests/OhhLensCoreTests/AppStoreTests.swift
git commit -m "feat: add loopback capture state to app store"
```

## Task 4: Surface Device Selection And Audio Flow In The UI

**Files:**
- Modify: `Sources/OhhLensApp/Views/LiveView.swift`
- Modify: `Sources/OhhLensApp/Views/SetupView.swift`

- [ ] **Step 1: Add the loopback UI elements**

Implementation requirements:
- In `LiveView`, show a `Picker` for loopback device selection when `selectedSource` is `.systemAudio` or `.appAudio`
- Show a clear status line: `No loopback device`, `Listening for audio`, or `Audio detected`
- Show the selected-device name in `SetupView`

- [ ] **Step 2: Build the app to verify the UI compiles**

Run:

```bash
swift build
```

Expected: PASS

- [ ] **Step 3: Commit the UI slice**

```bash
git add Sources/OhhLensApp/Views/LiveView.swift Sources/OhhLensApp/Views/SetupView.swift
git commit -m "feat: surface loopback capture controls"
```

## Task 5: End-To-End Verification For Virtual Device Capture

**Files:**
- Modify: `docs/qa/manual-smoke-checklist.md`

- [ ] **Step 1: Extend manual QA instructions**

Add checks for:
- BlackHole/loopback device appears in the picker
- Selecting system audio changes setup guidance
- Playing YouTube audio shows `Audio detected`
- Stopping playback returns to non-detected state

- [ ] **Step 2: Run the full verification sweep**

Run:

```bash
swift test
swift build
```

Expected: PASS

- [ ] **Step 3: Commit the verification slice**

```bash
git add docs/qa/manual-smoke-checklist.md
git commit -m "docs: add loopback capture smoke checks"
```

## Self-Review

Spec coverage:
- Virtual-device-first capture is covered by Tasks 1-5.
- Observable “audio is flowing” UX is covered by Tasks 2-4.
- User-facing setup guidance is covered by Tasks 4-5.
- Single-app audio support remains a later follow-up that can reuse this capture pipeline.

Gaps to watch during execution:
- This plan intentionally stops at verified audio flow into the app. If FunASR file-upload endpoints need a specific multipart or OpenAI-compatible shape, that should be its own follow-up slice using the server contract.
- AVFoundation device enumeration on macOS may require a small adaptation if the virtual device is only exposed through a lower-level CoreAudio path.

Placeholder scan:
- No unresolved TODO/TBD markers remain in the plan.

Type consistency:
- `AudioLevelSnapshot`, `AudioInputDevice`, and store properties are named consistently across tasks.
- `LoopbackCaptureService` remains the only concrete implementation point for system/app audio capture in this slice.
