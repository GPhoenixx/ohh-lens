# Ohh Lens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS app that captures local audio, manages a local FunASR backend, and shows live subtitles plus translation in a floating overlay and main desktop window.

**Architecture:** Use a package-first SwiftPM macOS app with a small SwiftUI `@main` executable target and a testable core module for state, services, persistence, and capture orchestration. Keep AppKit interop narrow and explicit for the overlay window and any window-level behaviors SwiftUI cannot express cleanly.

**Tech Stack:** Swift 6, SwiftUI, AppKit interop, AVFoundation, Process, URLSession, SwiftPM, XCTest

---

## File Structure

- `Package.swift`
  Swift package manifest with one executable target (`OhhLensApp`), one library target (`OhhLensCore`), and one test target.
- `App/OhhLensApp.swift`
  `@main` app entry point, scene model, and high-level dependency wiring.
- `App/AppDelegate.swift`
  Minimal app delegate for activation policy and launch-time setup.
- `Views/ContentView.swift`
  Root desktop composition and section routing.
- `Views/SidebarView.swift`
  Sidebar with `Live`, `History`, `Files`, and `Setup`.
- `Views/Live/LiveView.swift`
  Source selection, language selection, service status, and listening controls.
- `Views/History/HistoryView.swift`
  Session history, search, copy, reopen, and export actions.
- `Views/Files/FilesView.swift`
  Audio and video file import surface.
- `Views/Setup/SetupView.swift`
  Permissions, virtual device guidance, and backend diagnostics.
- `Views/Shared/StatusBadge.swift`
  Reusable service and capture status indicator.
- `Models/AppSection.swift`
  Main sidebar navigation enum.
- `Models/AudioSource.swift`
  Capture source types.
- `Models/CaptionMode.swift`
  Original, translation, or dual-line modes.
- `Models/LanguagePair.swift`
  Source and target language selection model.
- `Models/TranscriptSegment.swift`
  Timestamped transcript plus translation chunk.
- `Models/SessionRecord.swift`
  Session metadata and transcript history record.
- `Stores/AppStore.swift`
  Main app state and user actions.
- `Stores/HistoryStore.swift`
  Local history persistence and export helpers.
- `Services/ProcessRunner.swift`
  Small protocol around `Process` for testable backend launching.
- `Services/LocalServiceManager.swift`
  Start, stop, restart, and health-check the local FunASR process.
- `Services/FunASRClient.swift`
  Local HTTP client for transcription and translation requests.
- `Services/AudioChunkPipeline.swift`
  Normalizes capture buffers and files into chunk jobs sent to the backend.
- `Services/Capture/MicrophoneCaptureService.swift`
  Microphone capture.
- `Services/Capture/LoopbackCaptureService.swift`
  Virtual-device system and app-audio capture contract.
- `Services/Capture/FileTranscriptionService.swift`
  Imported file chunking path.
- `Services/Overlay/OverlayWindowController.swift`
  AppKit-backed always-on-top overlay window.
- `Services/Setup/PermissionsService.swift`
  Capture permission inspection and requests.
- `Services/Setup/VirtualDeviceDiagnostics.swift`
  Detect and describe loopback/virtual audio device readiness.
- `Support/AppPaths.swift`
  App support directories and file locations.
- `Support/Fixtures/`
  Small JSON and text fixtures for tests.
- `script/build_and_run.sh`
  Project-local run button bootstrap.
- `.codex/environments/environment.toml`
  Codex environment config for build/run.
- `Tests/OhhLensCoreTests/AppStoreTests.swift`
- `Tests/OhhLensCoreTests/LocalServiceManagerTests.swift`
- `Tests/OhhLensCoreTests/HistoryStoreTests.swift`
- `Tests/OhhLensCoreTests/AudioChunkPipelineTests.swift`
- `Tests/OhhLensCoreTests/VirtualDeviceDiagnosticsTests.swift`

## Scope Check

This is one integrated product, but the plan intentionally builds it in vertical slices:

1. package and desktop shell
2. app state and navigation
3. backend lifecycle
4. capture and chunking
5. overlay and live presentation
6. history and export
7. setup diagnostics and unhappy-path polish

Each slice produces working, testable software without requiring cloud services.

### Task 0: Bootstrap The Package-First macOS Workspace

**Files:**
- Create: `Package.swift`
- Create: `App/OhhLensApp.swift`
- Create: `App/AppDelegate.swift`
- Create: `Views/ContentView.swift`
- Create: `script/build_and_run.sh`
- Create: `.codex/environments/environment.toml`

- [ ] **Step 1: Initialize git at the project root**

Run:

```bash
git init
```

Expected: output includes `Initialized empty Git repository`

- [ ] **Step 2: Create the Swift package scaffold**

Run:

```bash
swift package init --type executable
mkdir -p App Views Views/Live Views/History Views/Files Views/Setup Views/Shared Models Stores Services Services/Capture Services/Overlay Services/Setup Support Tests/OhhLensCoreTests script .codex/environments
rm Sources/main.swift
mkdir -p Sources/OhhLensApp Sources/OhhLensCore
```

Expected: `Package.swift` exists and `swift package init` reports package creation

- [ ] **Step 3: Replace the scaffold with an app-ready package layout**

```swift
// Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OhhLens",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OhhLensCore", targets: ["OhhLensCore"]),
        .executable(name: "OhhLensApp", targets: ["OhhLensApp"])
    ],
    targets: [
        .target(
            name: "OhhLensCore",
            path: "Sources/OhhLensCore"
        ),
        .executableTarget(
            name: "OhhLensApp",
            dependencies: ["OhhLensCore"],
            path: "Sources/OhhLensApp"
        ),
        .testTarget(
            name: "OhhLensCoreTests",
            dependencies: ["OhhLensCore"],
            path: "Tests/OhhLensCoreTests"
        )
    ]
)
```

```swift
// Sources/OhhLensApp/OhhLensApp.swift
import SwiftUI
import OhhLensCore

@main
struct OhhLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appStore = AppStore.preview

    var body: some Scene {
        WindowGroup("Ohh Lens") {
            ContentView()
                .environmentObject(appStore)
                .frame(minWidth: 980, minHeight: 640)
        }

        Settings {
            SetupView()
                .environmentObject(appStore)
                .frame(width: 680, height: 520)
        }
    }
}
```

```swift
// Sources/OhhLensApp/AppDelegate.swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

```swift
// Sources/OhhLensApp/ContentView.swift
import SwiftUI
import OhhLensCore

struct ContentView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $appStore.selectedSection)
        } detail: {
            Text("Ohh Lens")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

```bash
#!/usr/bin/env bash
# script/build_and_run.sh
set -euo pipefail
swift build
swift run OhhLensApp
```

```toml
# .codex/environments/environment.toml
[run]
command = ["bash", "script/build_and_run.sh"]
```

- [ ] **Step 4: Run the app build to verify the shell compiles**

Run:

```bash
swift build
```

Expected: `Build complete!`

- [ ] **Step 5: Commit the bootstrap**

```bash
git add Package.swift Sources script .codex
git commit -m "chore: bootstrap package-first macOS app shell"
```

### Task 1: Add Core Models And App State With Tests First

**Files:**
- Create: `Sources/OhhLensCore/Models/AppSection.swift`
- Create: `Sources/OhhLensCore/Models/AudioSource.swift`
- Create: `Sources/OhhLensCore/Models/CaptionMode.swift`
- Create: `Sources/OhhLensCore/Models/LanguagePair.swift`
- Create: `Sources/OhhLensCore/Models/TranscriptSegment.swift`
- Create: `Sources/OhhLensCore/Models/SessionRecord.swift`
- Create: `Sources/OhhLensCore/Stores/AppStore.swift`
- Create: `Tests/OhhLensCoreTests/AppStoreTests.swift`
- Modify: `Sources/OhhLensApp/ContentView.swift`

- [ ] **Step 1: Write the failing app-state tests**

```swift
// Tests/OhhLensCoreTests/AppStoreTests.swift
import XCTest
@testable import OhhLensCore

final class AppStoreTests: XCTestCase {
    func test_defaultStateStartsOnLiveSectionWithDualLineCaptions() {
        let store = AppStore()

        XCTAssertEqual(store.selectedSection, .live)
        XCTAssertEqual(store.captionMode, .dualLine)
        XCTAssertEqual(store.selectedSource, .microphone)
    }

    func test_startListeningMarksSessionActive() {
        let store = AppStore()

        store.startListening()

        XCTAssertTrue(store.isListening)
        XCTAssertEqual(store.statusText, "Listening")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter AppStoreTests -v
```

Expected: FAIL with missing `AppStore`, `AppSection`, `CaptionMode`, or `AudioSource`

- [ ] **Step 3: Implement the minimal models and store**

```swift
// Sources/OhhLensCore/Models/AppSection.swift
public enum AppSection: String, CaseIterable, Identifiable {
    case live
    case history
    case files
    case setup

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}
```

```swift
// Sources/OhhLensCore/Models/AudioSource.swift
public enum AudioSource: String, CaseIterable, Identifiable {
    case microphone
    case systemAudio
    case appAudio
    case importedFile

    public var id: String { rawValue }
}
```

```swift
// Sources/OhhLensCore/Models/CaptionMode.swift
public enum CaptionMode: String, CaseIterable, Identifiable {
    case originalOnly
    case translationOnly
    case dualLine

    public var id: String { rawValue }
}
```

```swift
// Sources/OhhLensCore/Models/LanguagePair.swift
public struct LanguagePair: Equatable, Codable {
    public var source: String
    public var target: String

    public init(source: String = "auto", target: String = "en") {
        self.source = source
        self.target = target
    }
}
```

```swift
// Sources/OhhLensCore/Models/TranscriptSegment.swift
import Foundation

public struct TranscriptSegment: Equatable, Codable, Identifiable {
    public let id: UUID
    public let startedAt: TimeInterval
    public let endedAt: TimeInterval
    public let originalText: String
    public let translatedText: String?

    public init(
        id: UUID = UUID(),
        startedAt: TimeInterval,
        endedAt: TimeInterval,
        originalText: String,
        translatedText: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.originalText = originalText
        self.translatedText = translatedText
    }
}
```

```swift
// Sources/OhhLensCore/Models/SessionRecord.swift
import Foundation

public struct SessionRecord: Equatable, Codable, Identifiable {
    public let id: UUID
    public var source: AudioSource
    public var languages: LanguagePair
    public var createdAt: Date
    public var segments: [TranscriptSegment]

    public init(
        id: UUID = UUID(),
        source: AudioSource,
        languages: LanguagePair,
        createdAt: Date = .now,
        segments: [TranscriptSegment] = []
    ) {
        self.id = id
        self.source = source
        self.languages = languages
        self.createdAt = createdAt
        self.segments = segments
    }
}
```

```swift
// Sources/OhhLensCore/Stores/AppStore.swift
import Foundation
import Combine

@MainActor
public final class AppStore: ObservableObject {
    @Published public var selectedSection: AppSection = .live
    @Published public var selectedSource: AudioSource = .microphone
    @Published public var captionMode: CaptionMode = .dualLine
    @Published public var languagePair = LanguagePair(source: "auto", target: "en")
    @Published public var isListening = false
    @Published public var statusText = "Idle"
    @Published public var retainRawAudio = false

    public init() {}

    public func startListening() {
        isListening = true
        statusText = "Listening"
    }

    public func stopListening() {
        isListening = false
        statusText = "Idle"
    }
}

public extension AppStore {
    static var preview: AppStore { AppStore() }
}
```

```swift
// Sources/OhhLensApp/ContentView.swift
import SwiftUI
import OhhLensCore

struct ContentView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $appStore.selectedSection)
        } detail: {
            switch appStore.selectedSection {
            case .live:
                LiveView()
            case .history:
                HistoryView()
            case .files:
                FilesView()
            case .setup:
                SetupView()
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --filter AppStoreTests -v
```

Expected: PASS

- [ ] **Step 5: Commit the app-state slice**

```bash
git add Sources/OhhLensCore Tests/OhhLensCoreTests Sources/OhhLensApp/ContentView.swift
git commit -m "feat: add core app models and state store"
```

### Task 2: Implement Local Backend Lifecycle And Health Checks

**Files:**
- Create: `Sources/OhhLensCore/Services/ProcessRunner.swift`
- Create: `Sources/OhhLensCore/Services/LocalServiceManager.swift`
- Create: `Sources/OhhLensCore/Services/FunASRClient.swift`
- Create: `Tests/OhhLensCoreTests/LocalServiceManagerTests.swift`
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`

- [ ] **Step 1: Write the failing backend lifecycle tests**

```swift
// Tests/OhhLensCoreTests/LocalServiceManagerTests.swift
import XCTest
@testable import OhhLensCore

final class LocalServiceManagerTests: XCTestCase {
    func test_startTransitionsToReadyWhenHealthCheckSucceeds() async throws {
        let runner = StubProcessRunner()
        let client = StubFunASRClient(healthResult: true)
        let manager = LocalServiceManager(processRunner: runner, client: client)

        try await manager.start()

        XCTAssertEqual(manager.status, .ready)
        XCTAssertEqual(runner.launchCount, 1)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter LocalServiceManagerTests/test_startTransitionsToReadyWhenHealthCheckSucceeds -v
```

Expected: FAIL with missing `LocalServiceManager`, `StubProcessRunner`, or `StubFunASRClient`

- [ ] **Step 3: Implement the service manager and client seam**

```swift
// Sources/OhhLensCore/Services/ProcessRunner.swift
import Foundation

public protocol ProcessRunning {
    func launch(executableURL: URL, arguments: [String]) throws
    func terminate()
}

public final class ProcessRunner: ProcessRunning {
    private let process = Process()

    public init() {}

    public func launch(executableURL: URL, arguments: [String]) throws {
        process.executableURL = executableURL
        process.arguments = arguments
        try process.run()
    }

    public func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }
}
```

```swift
// Sources/OhhLensCore/Services/FunASRClient.swift
import Foundation

public protocol FunASRServicing {
    func healthCheck() async -> Bool
}

public struct FunASRClient: FunASRServicing {
    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    public func healthCheck() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 1

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
```

```swift
// Sources/OhhLensCore/Services/LocalServiceManager.swift
import Foundation

@MainActor
public final class LocalServiceManager: ObservableObject {
    public enum Status: Equatable {
        case idle
        case starting
        case ready
        case needsAttention(String)
    }

    @Published public private(set) var status: Status = .idle

    private let processRunner: ProcessRunning
    private let client: FunASRServicing

    public init(processRunner: ProcessRunning, client: FunASRServicing) {
        self.processRunner = processRunner
        self.client = client
    }

    public func start() async throws {
        status = .starting
        try processRunner.launch(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["bash", "-lc", "echo starting-funasr"]
        )

        if await client.healthCheck() {
            status = .ready
        } else {
            status = .needsAttention("FunASR health check failed")
        }
    }

    public func stop() {
        processRunner.terminate()
        status = .idle
    }
}
```

```swift
// Append inside Tests/OhhLensCoreTests/LocalServiceManagerTests.swift
private final class StubProcessRunner: ProcessRunning {
    var launchCount = 0
    func launch(executableURL: URL, arguments: [String]) throws { launchCount += 1 }
    func terminate() {}
}

private struct StubFunASRClient: FunASRServicing {
    let healthResult: Bool
    func healthCheck() async -> Bool { healthResult }
}
```

```swift
// Add to Sources/OhhLensCore/Stores/AppStore.swift
@Published public var backendStatusText = "Backend idle"

public func updateBackendStatus(_ text: String) {
    backendStatusText = text
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --filter LocalServiceManagerTests -v
```

Expected: PASS

- [ ] **Step 5: Commit the backend lifecycle slice**

```bash
git add Sources/OhhLensCore/Services Sources/OhhLensCore/Stores Tests/OhhLensCoreTests
git commit -m "feat: add local FunASR lifecycle management"
```

### Task 3: Build The Audio Chunk Pipeline For Mic, Loopback, And Files

**Files:**
- Create: `Sources/OhhLensCore/Services/AudioChunkPipeline.swift`
- Create: `Sources/OhhLensCore/Services/Capture/MicrophoneCaptureService.swift`
- Create: `Sources/OhhLensCore/Services/Capture/LoopbackCaptureService.swift`
- Create: `Sources/OhhLensCore/Services/Capture/FileTranscriptionService.swift`
- Create: `Tests/OhhLensCoreTests/AudioChunkPipelineTests.swift`
- Modify: `Sources/OhhLensCore/Models/SessionRecord.swift`

- [ ] **Step 1: Write the failing chunking tests**

```swift
// Tests/OhhLensCoreTests/AudioChunkPipelineTests.swift
import XCTest
@testable import OhhLensCore

final class AudioChunkPipelineTests: XCTestCase {
    func test_appendChunkAddsTimestampedSegmentPlaceholder() {
        let pipeline = AudioChunkPipeline()
        let session = pipeline.beginSession(source: .microphone, languages: .init(source: "auto", target: "vi"))

        let updated = pipeline.appendChunk(
            data: Data([0x00, 0x01]),
            transcript: "hello",
            translation: "xin chao",
            to: session
        )

        XCTAssertEqual(updated.segments.count, 1)
        XCTAssertEqual(updated.segments.first?.translatedText, "xin chao")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter AudioChunkPipelineTests -v
```

Expected: FAIL with missing `AudioChunkPipeline`

- [ ] **Step 3: Implement the minimal session pipeline and service contracts**

```swift
// Sources/OhhLensCore/Services/AudioChunkPipeline.swift
import Foundation

public struct AudioChunkPipeline {
    public init() {}

    public func beginSession(source: AudioSource, languages: LanguagePair) -> SessionRecord {
        SessionRecord(source: source, languages: languages)
    }

    public func appendChunk(
        data: Data,
        transcript: String,
        translation: String?,
        to session: SessionRecord
    ) -> SessionRecord {
        var updated = session
        let segment = TranscriptSegment(
            startedAt: Date.now.timeIntervalSince1970,
            endedAt: Date.now.timeIntervalSince1970,
            originalText: transcript,
            translatedText: translation
        )
        updated.segments.append(segment)
        return updated
    }
}
```

```swift
// Sources/OhhLensCore/Services/Capture/MicrophoneCaptureService.swift
import Foundation

public protocol AudioCaptureServicing {
    var source: AudioSource { get }
    func start() throws
    func stop()
}

public final class MicrophoneCaptureService: AudioCaptureServicing {
    public let source: AudioSource = .microphone
    public init() {}
    public func start() throws {}
    public func stop() {}
}
```

```swift
// Sources/OhhLensCore/Services/Capture/LoopbackCaptureService.swift
import Foundation

public final class LoopbackCaptureService: AudioCaptureServicing {
    public let source: AudioSource

    public init(source: AudioSource) {
        self.source = source
    }

    public func start() throws {}
    public func stop() {}
}
```

```swift
// Sources/OhhLensCore/Services/Capture/FileTranscriptionService.swift
import Foundation

public struct FileTranscriptionRequest {
    public let fileURL: URL
    public let languages: LanguagePair

    public init(fileURL: URL, languages: LanguagePair) {
        self.fileURL = fileURL
        self.languages = languages
    }
}

public final class FileTranscriptionService {
    public init() {}

    public func makeRequest(fileURL: URL, languages: LanguagePair) -> FileTranscriptionRequest {
        FileTranscriptionRequest(fileURL: fileURL, languages: languages)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --filter AudioChunkPipelineTests -v
```

Expected: PASS

- [ ] **Step 5: Commit the capture pipeline slice**

```bash
git add Sources/OhhLensCore/Services Sources/OhhLensCore/Models Tests/OhhLensCoreTests
git commit -m "feat: add audio chunk pipeline and capture service contracts"
```

### Task 4: Build The Main Window, Sidebar, And Live Overlay

**Files:**
- Create: `Sources/OhhLensApp/SidebarView.swift`
- Create: `Sources/OhhLensApp/Views/LiveView.swift`
- Create: `Sources/OhhLensApp/Views/HistoryView.swift`
- Create: `Sources/OhhLensApp/Views/FilesView.swift`
- Create: `Sources/OhhLensApp/Views/SetupView.swift`
- Create: `Sources/OhhLensApp/Views/Shared/StatusBadge.swift`
- Create: `Sources/OhhLensCore/Services/Overlay/OverlayWindowController.swift`
- Modify: `Sources/OhhLensApp/ContentView.swift`

- [ ] **Step 1: Write a failing UI smoke test around overlay mode defaults**

```swift
// Append inside Tests/OhhLensCoreTests/AppStoreTests.swift
func test_overlayModeCanSwitchBetweenAllThreeDisplayModes() {
    let store = AppStore()

    store.captionMode = .originalOnly
    XCTAssertEqual(store.captionMode, .originalOnly)

    store.captionMode = .translationOnly
    XCTAssertEqual(store.captionMode, .translationOnly)

    store.captionMode = .dualLine
    XCTAssertEqual(store.captionMode, .dualLine)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter AppStoreTests/test_overlayModeCanSwitchBetweenAllThreeDisplayModes -v
```

Expected: FAIL until the UI targets and bindings compile cleanly

- [ ] **Step 3: Implement the desktop surfaces and overlay controller**

```swift
// Sources/OhhLensApp/SidebarView.swift
import SwiftUI
import OhhLensCore

struct SidebarView: View {
    @Binding var selection: AppSection

    var body: some View {
        List(AppSection.allCases, selection: $selection) { section in
            Text(section.title)
                .tag(section)
        }
        .listStyle(.sidebar)
        .navigationTitle("Ohh Lens")
    }
}
```

```swift
// Sources/OhhLensApp/Views/Shared/StatusBadge.swift
import SwiftUI

struct StatusBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }
}
```

```swift
// Sources/OhhLensApp/Views/LiveView.swift
import SwiftUI
import OhhLensCore

struct LiveView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Live")
                    .font(.largeTitle.bold())
                Spacer()
                StatusBadge(text: appStore.statusText)
            }

            Picker("Source", selection: $appStore.selectedSource) {
                ForEach(AudioSource.allCases) { source in
                    Text(source.id).tag(source)
                }
            }

            Picker("Caption mode", selection: $appStore.captionMode) {
                ForEach(CaptionMode.allCases) { mode in
                    Text(mode.id).tag(mode)
                }
            }

            HStack {
                Button("Start Listening") { appStore.startListening() }
                Button("Stop") { appStore.stopListening() }
            }

            Spacer()
        }
        .padding(24)
    }
}
```

```swift
// Sources/OhhLensApp/Views/HistoryView.swift
import SwiftUI

struct HistoryView: View {
    var body: some View {
        Text("History")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

```swift
// Sources/OhhLensApp/Views/FilesView.swift
import SwiftUI

struct FilesView: View {
    var body: some View {
        Text("Files")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

```swift
// Sources/OhhLensApp/Views/SetupView.swift
import SwiftUI
import OhhLensCore

struct SetupView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Setup")
                .font(.title.bold())
            Text(appStore.backendStatusText)
            Spacer()
        }
        .padding(24)
    }
}
```

```swift
// Sources/OhhLensCore/Services/Overlay/OverlayWindowController.swift
import SwiftUI
import AppKit

@MainActor
public final class OverlayWindowController {
    private var window: NSWindow?

    public init() {}

    public func present<Content: View>(@ViewBuilder content: () -> Content) {
        let hosting = NSHostingView(rootView: content())
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 720, height: 140),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
```

- [ ] **Step 4: Run the app build and the focused tests**

Run:

```bash
swift test --filter AppStoreTests -v
swift build
```

Expected: tests PASS and app build succeeds

- [ ] **Step 5: Commit the UI shell**

```bash
git add Sources/OhhLensApp Sources/OhhLensCore/Services/Overlay Tests/OhhLensCoreTests
git commit -m "feat: add desktop shell and overlay scaffolding"
```

### Task 5: Add History Persistence And Export

**Files:**
- Create: `Sources/OhhLensCore/Stores/HistoryStore.swift`
- Create: `Sources/OhhLensCore/Support/AppPaths.swift`
- Create: `Tests/OhhLensCoreTests/HistoryStoreTests.swift`
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`
- Modify: `Sources/OhhLensApp/Views/HistoryView.swift`

- [ ] **Step 1: Write the failing history persistence tests**

```swift
// Tests/OhhLensCoreTests/HistoryStoreTests.swift
import XCTest
@testable import OhhLensCore

final class HistoryStoreTests: XCTestCase {
    func test_saveAndReloadRoundTripsSessionRecords() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HistoryStore(baseDirectory: tempDirectory)
        let session = SessionRecord(source: .microphone, languages: .init(source: "auto", target: "en"))

        try store.save([session])
        let reloaded = try store.load()

        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.source, .microphone)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter HistoryStoreTests -v
```

Expected: FAIL with missing `HistoryStore`

- [ ] **Step 3: Implement local history persistence and wire it into the UI**

```swift
// Sources/OhhLensCore/Support/AppPaths.swift
import Foundation

public enum AppPaths {
    public static func supportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("OhhLens", isDirectory: true)
    }
}
```

```swift
// Sources/OhhLensCore/Stores/HistoryStore.swift
import Foundation

public final class HistoryStore {
    private let fileURL: URL

    public init(baseDirectory: URL) {
        self.fileURL = baseDirectory.appendingPathComponent("history.json")
    }

    public func save(_ sessions: [SessionRecord]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(sessions)
        try data.write(to: fileURL)
    }

    public func load() throws -> [SessionRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([SessionRecord].self, from: data)
    }

    public func exportSRT(for session: SessionRecord) -> String {
        session.segments.enumerated().map { index, segment in
            let cue = index + 1
            let original = segment.originalText
            let translated = segment.translatedText.map { "\n\($0)" } ?? ""
            return """
            \(cue)
            00:00:00,000 --> 00:00:02,000
            \(original)\(translated)
            """
        }
        .joined(separator: "\n\n")
    }
}
```

```swift
// Add to Sources/OhhLensCore/Stores/AppStore.swift
@Published public var history: [SessionRecord] = []
```

```swift
// Sources/OhhLensApp/Views/HistoryView.swift
import SwiftUI
import OhhLensCore

struct HistoryView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        List(appStore.history) { session in
            VStack(alignment: .leading) {
                Text(session.source.id)
                    .font(.headline)
                Text(session.createdAt.formatted())
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("History")
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --filter HistoryStoreTests -v
```

Expected: PASS

- [ ] **Step 5: Commit the history slice**

```bash
git add Sources/OhhLensCore/Stores Sources/OhhLensCore/Support Sources/OhhLensApp/Views/HistoryView.swift Tests/OhhLensCoreTests
git commit -m "feat: add local history persistence"
```

### Task 6: Add Setup Diagnostics And Unhappy-Path UX

**Files:**
- Create: `Sources/OhhLensCore/Services/Setup/PermissionsService.swift`
- Create: `Sources/OhhLensCore/Services/Setup/VirtualDeviceDiagnostics.swift`
- Create: `Tests/OhhLensCoreTests/VirtualDeviceDiagnosticsTests.swift`
- Modify: `Sources/OhhLensApp/Views/SetupView.swift`
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`

- [ ] **Step 1: Write the failing diagnostics tests**

```swift
// Tests/OhhLensCoreTests/VirtualDeviceDiagnosticsTests.swift
import XCTest
@testable import OhhLensCore

final class VirtualDeviceDiagnosticsTests: XCTestCase {
    func test_missingVirtualDeviceReturnsNeedsAttentionMessage() {
        let diagnostics = VirtualDeviceDiagnostics(availableDeviceNames: [])

        let result = diagnostics.currentStatus()

        XCTAssertEqual(result.state, .needsAttention)
        XCTAssertTrue(result.message.contains("virtual audio device"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter VirtualDeviceDiagnosticsTests -v
```

Expected: FAIL with missing `VirtualDeviceDiagnostics`

- [ ] **Step 3: Implement setup diagnostics and route them into Setup**

```swift
// Sources/OhhLensCore/Services/Setup/PermissionsService.swift
import Foundation

public struct PermissionsSnapshot: Equatable {
    public var microphoneAuthorized: Bool

    public init(microphoneAuthorized: Bool) {
        self.microphoneAuthorized = microphoneAuthorized
    }
}

public struct PermissionsService {
    public init() {}

    public func currentSnapshot() -> PermissionsSnapshot {
        PermissionsSnapshot(microphoneAuthorized: true)
    }
}
```

```swift
// Sources/OhhLensCore/Services/Setup/VirtualDeviceDiagnostics.swift
import Foundation

public struct VirtualDeviceStatus: Equatable {
    public enum State: Equatable {
        case ready
        case needsAttention
    }

    public var state: State
    public var message: String
}

public struct VirtualDeviceDiagnostics {
    public let availableDeviceNames: [String]

    public init(availableDeviceNames: [String]) {
        self.availableDeviceNames = availableDeviceNames
    }

    public func currentStatus() -> VirtualDeviceStatus {
        if availableDeviceNames.isEmpty {
            return .init(
                state: .needsAttention,
                message: "No virtual audio device found. Install and route system audio through the helper device."
            )
        }

        return .init(state: .ready, message: "Virtual audio device detected.")
    }
}
```

```swift
// Add to Sources/OhhLensCore/Stores/AppStore.swift
@Published public var setupMessage = "Checking setup…"
```

```swift
// Sources/OhhLensApp/Views/SetupView.swift
import SwiftUI
import OhhLensCore

struct SetupView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Setup")
                .font(.title.bold())
            Text(appStore.backendStatusText)
            Text(appStore.setupMessage)
                .foregroundStyle(.secondary)
            Button("Open System Settings") {}
            Spacer()
        }
        .padding(24)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --filter VirtualDeviceDiagnosticsTests -v
```

Expected: PASS

- [ ] **Step 5: Commit the setup slice**

```bash
git add Sources/OhhLensCore/Services/Setup Sources/OhhLensCore/Stores Sources/OhhLensApp/Views/SetupView.swift Tests/OhhLensCoreTests
git commit -m "feat: add setup diagnostics and recovery messaging"
```

### Task 7: Wire The First End-To-End Vertical Slice And Verify It

**Files:**
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`
- Modify: `Sources/OhhLensApp/Views/LiveView.swift`
- Modify: `Sources/OhhLensApp/Views/FilesView.swift`
- Modify: `Sources/OhhLensApp/Views/HistoryView.swift`
- Modify: `script/build_and_run.sh`
- Create: `docs/qa/manual-smoke-checklist.md`

- [ ] **Step 1: Write a failing integration-oriented store test**

```swift
// Append inside Tests/OhhLensCoreTests/AppStoreTests.swift
func test_stopListeningReturnsToIdleState() {
    let store = AppStore()
    store.startListening()

    store.stopListening()

    XCTAssertFalse(store.isListening)
    XCTAssertEqual(store.statusText, "Idle")
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter AppStoreTests/test_stopListeningReturnsToIdleState -v
```

Expected: FAIL until the latest state wiring compiles after all previous tasks

- [ ] **Step 3: Finish the first vertical slice and add QA instructions**

```swift
// Update Sources/OhhLensCore/Stores/AppStore.swift
public func applyPreviewTranscript() {
    let segment = TranscriptSegment(
        startedAt: Date.now.timeIntervalSince1970,
        endedAt: Date.now.timeIntervalSince1970,
        originalText: "We can start the meeting now if everyone is ready.",
        translatedText: "Chung ta co the bat dau cuoc hop ngay bay gio."
    )
    history = [
        SessionRecord(
            source: selectedSource,
            languages: languagePair,
            segments: [segment]
        )
    ]
}
```

```swift
// Update Sources/OhhLensApp/Views/LiveView.swift
Button("Load Preview Subtitle") {
    appStore.applyPreviewTranscript()
}
```

```swift
// Update Sources/OhhLensApp/Views/FilesView.swift
import SwiftUI

struct FilesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Files")
                .font(.largeTitle.bold())
            Text("Import audio or video files for local transcription and translation.")
            Spacer()
        }
        .padding(24)
    }
}
```

```bash
#!/usr/bin/env bash
# script/build_and_run.sh
set -euo pipefail
swift test
swift build
swift run OhhLensApp
```

```markdown
# docs/qa/manual-smoke-checklist.md

- Launch the app and confirm the main window opens.
- Switch through Live, History, Files, and Setup.
- Start and stop listening.
- Change caption mode between original, translation, and dual-line.
- Confirm Setup shows backend and virtual-device guidance.
- Confirm History can show a saved preview transcript.
```

- [ ] **Step 4: Run the full verification**

Run:

```bash
swift test
swift build
```

Expected: all tests PASS and build succeeds

- [ ] **Step 5: Commit the first shippable vertical slice**

```bash
git add Sources Tests script docs/qa
git commit -m "feat: wire first end-to-end ohh lens experience"
```

## Self-Review

Spec coverage:

- Main window, overlay, setup, history, file import surface, and live view are all covered by Tasks 0, 4, 5, 6, and 7.
- Local backend lifecycle and health checks are covered by Task 2.
- Microphone, loopback, and file pipeline contracts are covered by Task 3.
- Local history, exports groundwork, and retention defaults are covered by Tasks 1, 5, and 7.
- Accessibility and desktop structure are reflected in the SwiftUI/AppKit split and the package-first file layout.

Gaps to watch during execution:

- Real AVFoundation capture and actual FunASR request payloads must replace the minimal contracts written in early tasks before calling the app feature-complete.
- Overlay content must be upgraded from scaffold to real transcript rendering before calling the feature complete.

Placeholder scan:

- No unresolved placeholder markers or deferred implementation notes are left in the task instructions.

Type consistency:

- `AppStore`, `AudioSource`, `CaptionMode`, `LanguagePair`, `SessionRecord`, and `TranscriptSegment` are defined before later tasks depend on them.
- `LocalServiceManager` uses the same `FunASRServicing` and `ProcessRunning` names referenced in tests and later store wiring.
