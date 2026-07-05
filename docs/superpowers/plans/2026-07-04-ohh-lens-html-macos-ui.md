# Ohh Lens HTML-Matched macOS UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the native Ohh Lens macOS interface so it matches the approved HTML reference, including the five-tab shell, glass styling, screen layouts, and native PiP overlay wiring.

**Architecture:** Keep the existing audio, history, and setup services intact, but replace the current `NavigationSplitView` presentation layer with a custom SwiftUI shell driven by expanded `AppStore` UI state. Build a reusable desktop design system first, then migrate each HTML-matched screen to shared components so styling stays consistent and state remains centralized.

**Tech Stack:** SwiftUI, AppKit window hosting for PiP, Observation (`@Observable`), Xcode macOS app target, XCTest

---

## File Structure

### Existing files to modify

- `Sources/OhhLensApp/ContentView.swift`
  Responsible for replacing `NavigationSplitView` with the custom HTML-matched shell.
- `Sources/OhhLensApp/SidebarView.swift`
  Responsible for becoming the custom grouped sidebar that matches the HTML navigation.
- `Sources/OhhLensApp/Views/LiveView.swift`
  Responsible for the `Live Subtitles` screen.
- `Sources/OhhLensApp/Views/HistoryView.swift`
  Responsible for becoming the `Saved Transcripts` two-pane archive view.
- `Sources/OhhLensApp/Views/FilesView.swift`
  Responsible for becoming the `File Transcriber` workflow.
- `Sources/OhhLensApp/Views/SetupView.swift`
  Responsible for becoming the `App Settings` screen.
- `Sources/OhhLensCore/Models/AppSection.swift`
  Responsible for the new five-tab app shell enum and HTML-matched labels.
- `Sources/OhhLensCore/Stores/AppStore.swift`
  Responsible for new tab state, file-transcriber state, transcript-selection state, and PiP state.
- `Sources/OhhLensCore/Services/Overlay/OverlayWindowController.swift`
  Responsible for the HTML-matched native PiP window behavior.
- `Tests/OhhLensCoreTests/AppStoreTests.swift`
  Responsible for coverage of the new default tab structure and UI state transitions.

### New files to create

- `Sources/OhhLensApp/Views/ConversationsView.swift`
  New screen for the HTML `Conversations` tab.
- `Sources/OhhLensApp/Views/Shared/AppChrome.swift`
  Shared window shell, titlebar spacer, and main panel container styles.
- `Sources/OhhLensApp/Views/Shared/AppTheme.swift`
  Centralized colors, spacing, corner radii, and button/card appearance helpers.
- `Sources/OhhLensApp/Views/Shared/GlassCard.swift`
  Reusable glass-like card wrapper for HTML-style content panes.
- `Sources/OhhLensApp/Views/Shared/TranscriptWidgets.swift`
  Shared transcript rows, bubble views, and empty states.
- `Sources/OhhLensCore/Models/FileTranscriptionViewState.swift`
  Explicit UI state for idle, processing, and completed file transcription phases.
- `Sources/OhhLensCore/Models/HistoryViewerState.swift`
  UI state for selected transcript, search text, and viewer controls.
- `Sources/OhhLensCore/Models/PiPViewState.swift`
  UI state for PiP visibility and caption presentation.

### Tests to add or extend

- `Tests/OhhLensCoreTests/AppStoreTests.swift`
  Add tests for:
  - five-tab default shell state
  - file-transcriber phase transitions
  - history viewer selection/search state
  - PiP open/close state

---

### Task 1: Expand App Shell and UI State

**Files:**
- Create: `Sources/OhhLensCore/Models/FileTranscriptionViewState.swift`
- Create: `Sources/OhhLensCore/Models/HistoryViewerState.swift`
- Create: `Sources/OhhLensCore/Models/PiPViewState.swift`
- Modify: `Sources/OhhLensCore/Models/AppSection.swift`
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`
- Test: `Tests/OhhLensCoreTests/AppStoreTests.swift`

- [ ] **Step 1: Write failing tests for the new default shell and UI state**

```swift
@MainActor
func test_defaultStateStartsOnLiveSubtitlesTab() {
    let store = AppStore()

    XCTAssertEqual(store.selectedSection, .liveSubtitles)
}

@MainActor
func test_fileTranscriptionStateStartsIdle() {
    let store = AppStore()

    XCTAssertEqual(store.fileTranscription.phase, .idle)
    XCTAssertNil(store.fileTranscription.selectedFileURL)
}

@MainActor
func test_historyViewerStartsWithFirstHistoryItemSelectedWhenPreviewLoaded() {
    let store = AppStore()

    store.applyPreviewTranscript()

    XCTAssertEqual(store.historyViewer.selectedSessionID, store.history.first?.id)
}

@MainActor
func test_pipStateCanToggleVisibility() {
    let store = AppStore()

    XCTAssertFalse(store.pipState.isVisible)
    store.togglePiP()
    XCTAssertTrue(store.pipState.isVisible)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS' -only-testing:OhhLensTests/AppStoreTests`

Expected: FAIL with missing enum cases and missing `fileTranscription`, `historyViewer`, or `pipState` properties on `AppStore`.

- [ ] **Step 3: Add the new app section enum and view-state models**

```swift
public enum AppSection: String, CaseIterable, Identifiable {
    case liveSubtitles
    case conversations
    case fileTranscriber
    case savedTranscripts
    case appSettings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .liveSubtitles: "Live Subtitles"
        case .conversations: "Conversations"
        case .fileTranscriber: "File Transcriber"
        case .savedTranscripts: "Saved Transcripts"
        case .appSettings: "App Settings"
        }
    }
}
```

```swift
public struct FileTranscriptionViewState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case processing
        case completed
    }

    public var phase: Phase = .idle
    public var selectedFileURL: URL?
    public var progress: Double = 0
    public var currentStep: String?
    public var completedLines: [String] = []
}
```

```swift
public struct HistoryViewerState: Equatable, Sendable {
    public var selectedSessionID: SessionRecord.ID?
    public var searchText: String = ""
    public var translationTarget: String = "none"
}
```

```swift
public struct PiPViewState: Equatable, Sendable {
    public var isVisible: Bool = false
    public var fontSize: Double = 14
    public var opacity: Double = 0.8
}
```

- [ ] **Step 4: Extend `AppStore` with explicit UI state and helpers**

```swift
public var selectedSection: AppSection = .liveSubtitles
public var fileTranscription = FileTranscriptionViewState()
public var historyViewer = HistoryViewerState()
public var pipState = PiPViewState()

public func selectHistorySession(_ id: SessionRecord.ID?) {
    historyViewer.selectedSessionID = id
}

public func updateHistorySearch(_ text: String) {
    historyViewer.searchText = text
}

public func togglePiP() {
    pipState.isVisible.toggle()
}

public func beginFileTranscription(for fileURL: URL) {
    fileTranscription.selectedFileURL = fileURL
    fileTranscription.phase = .processing
    fileTranscription.progress = 0
    fileTranscription.currentStep = "Extracting audio channel"
}

public func completeFileTranscription(lines: [String]) {
    fileTranscription.phase = .completed
    fileTranscription.progress = 1
    fileTranscription.completedLines = lines
}
```

- [ ] **Step 5: Keep history viewer selection synchronized with available history**

```swift
public var history: [SessionRecord] = [] {
    didSet {
        persistHistory()

        if historyViewer.selectedSessionID == nil {
            historyViewer.selectedSessionID = history.first?.id
        } else if history.contains(where: { $0.id == historyViewer.selectedSessionID }) == false {
            historyViewer.selectedSessionID = history.first?.id
        }
    }
}
```

- [ ] **Step 6: Run tests to verify the new state model passes**

Run: `xcodebuild test -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS' -only-testing:OhhLensTests/AppStoreTests`

Expected: PASS for the new `AppStoreTests` cases.

- [ ] **Step 7: Commit**

```bash
git add Sources/OhhLensCore/Models/AppSection.swift \
  Sources/OhhLensCore/Models/FileTranscriptionViewState.swift \
  Sources/OhhLensCore/Models/HistoryViewerState.swift \
  Sources/OhhLensCore/Models/PiPViewState.swift \
  Sources/OhhLensCore/Stores/AppStore.swift \
  Tests/OhhLensCoreTests/AppStoreTests.swift
git commit -m "feat: add html-matched app shell state"
```

---

### Task 2: Build Shared HTML-Matched Shell and Design System

**Files:**
- Create: `Sources/OhhLensApp/Views/Shared/AppTheme.swift`
- Create: `Sources/OhhLensApp/Views/Shared/AppChrome.swift`
- Create: `Sources/OhhLensApp/Views/Shared/GlassCard.swift`
- Modify: `Sources/OhhLensApp/SidebarView.swift`
- Modify: `Sources/OhhLensApp/ContentView.swift`
- Test: `xcodebuild build -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS'`

- [ ] **Step 1: Write the failing shell build change**

Replace the old `NavigationSplitView` usage in `ContentView.swift` with a temporary reference to a new shell container so the compiler fails until the shared chrome exists.

```swift
var body: some View {
    AppChromeLayout {
        SidebarView(selection: $appStore.selectedSection)
    } detail: {
        Text("Placeholder")
    }
}
```

- [ ] **Step 2: Run build to verify it fails**

Run: `xcodebuild build -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS'`

Expected: FAIL with `cannot find 'AppChromeLayout' in scope`.

- [ ] **Step 3: Create shared theme tokens and glass card wrapper**

```swift
enum AppTheme {
    static let accent = Color(red: 0.859, green: 0.051, blue: 0.063)
    static let textPrimary = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let textMuted = Color(red: 0.42, green: 0.42, blue: 0.42)
    static let sidebarGlass = Color.white.opacity(0.62)
    static let windowGlass = Color.white.opacity(0.72)
    static let cardGlass = Color.white.opacity(0.45)
}
```

```swift
struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .background(AppTheme.cardGlass, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.gray.opacity(0.18), lineWidth: 1)
            }
    }
}
```

- [ ] **Step 4: Create the custom shell layout and grouped sidebar**

```swift
struct AppChromeLayout<Sidebar: View, Detail: View>: View {
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let detail: Detail

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 230)
                .background(AppTheme.sidebarGlass)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 56)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(AppTheme.windowGlass)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
```

```swift
ForEach(sidebarSections) { item in
    Button {
        selection = item.section
    } label: {
        Label(item.section.title, systemImage: item.symbol)
            .foregroundStyle(item.section == selection ? Color.white : AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(item.section == selection ? AppTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
}
```

- [ ] **Step 5: Switch `ContentView` to the HTML-matched tab router**

```swift
switch appStore.selectedSection {
case .liveSubtitles:
    LiveView()
case .conversations:
    ConversationsView()
case .fileTranscriber:
    FilesView()
case .savedTranscripts:
    HistoryView()
case .appSettings:
    SetupView()
}
```

- [ ] **Step 6: Run build to verify the shell compiles**

Run: `xcodebuild build -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Sources/OhhLensApp/ContentView.swift \
  Sources/OhhLensApp/SidebarView.swift \
  Sources/OhhLensApp/Views/Shared/AppTheme.swift \
  Sources/OhhLensApp/Views/Shared/AppChrome.swift \
  Sources/OhhLensApp/Views/Shared/GlassCard.swift
git commit -m "feat: add html-matched app shell"
```

---

### Task 3: Implement Live Subtitles and Conversations Screens

**Files:**
- Create: `Sources/OhhLensApp/Views/ConversationsView.swift`
- Create: `Sources/OhhLensApp/Views/Shared/TranscriptWidgets.swift`
- Modify: `Sources/OhhLensApp/Views/LiveView.swift`
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`
- Test: `Tests/OhhLensCoreTests/AppStoreTests.swift`

- [ ] **Step 1: Write a failing test for conversation transcript presentation state**

```swift
@MainActor
func test_liveTranscriptStateExposesConversationRowsFromFinalizedLines() {
    let store = AppStore()

    store.handleStreamingEvent(.final("Speaker A: Hello there"))
    store.handleStreamingEvent(.final("Speaker B: Hi back"))

    XCTAssertEqual(store.conversationRows.count, 2)
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `xcodebuild test -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS' -only-testing:OhhLensTests/AppStoreTests/test_liveTranscriptStateExposesConversationRowsFromFinalizedLines`

Expected: FAIL with missing `conversationRows`.

- [ ] **Step 3: Add shared transcript widgets and conversation row state**

```swift
public struct ConversationRow: Equatable, Identifiable, Sendable {
    public let id = UUID()
    public let speaker: String
    public let text: String
    public let timestampLabel: String
}
```

```swift
public var conversationRows: [ConversationRow] {
    liveTranscriptState.finalizedCaptionLines.enumerated().map { index, line in
        ConversationRow(
            speaker: index.isMultiple(of: 2) ? "Speaker A" : "Speaker B",
            text: line,
            timestampLabel: "00:\(String(format: "%02d", index * 4 + 2))"
        )
    }
}
```

- [ ] **Step 4: Rebuild `LiveView` to match the HTML layout**

```swift
GlassCard {
    VStack(spacing: 0) {
        captionViewport
        Divider().padding(.top, 14)
        liveFooterControls
    }
}
```

```swift
private var header: some View {
    HStack {
        HStack(spacing: 12) {
            Text("Live Subtitles")
                .font(.system(size: 24, weight: .bold))
            loopbackPicker
        }
        Spacer()
        pipToggleButton
    }
}
```

- [ ] **Step 5: Add `ConversationsView` as a sibling live mode**

```swift
struct ConversationsView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sharedConversationHeader

            GlassCard {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(appStore.conversationRows) { row in
                                ConversationBubble(row: row)
                            }
                        }
                    }

                    Divider().padding(.top, 14)
                    liveFooterControls
                }
            }
        }
    }
}
```

- [ ] **Step 6: Run tests and build**

Run: `xcodebuild test -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS' -only-testing:OhhLensTests/AppStoreTests`

Expected: PASS.

Run: `xcodebuild build -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Sources/OhhLensApp/Views/LiveView.swift \
  Sources/OhhLensApp/Views/ConversationsView.swift \
  Sources/OhhLensApp/Views/Shared/TranscriptWidgets.swift \
  Sources/OhhLensCore/Stores/AppStore.swift \
  Tests/OhhLensCoreTests/AppStoreTests.swift
git commit -m "feat: implement html-matched live transcript views"
```

---

### Task 4: Implement File Transcriber Screen and State Flow

**Files:**
- Modify: `Sources/OhhLensApp/Views/FilesView.swift`
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`
- Modify: `Sources/OhhLensCore/Services/Capture/FileTranscriptionService.swift`
- Test: `Tests/OhhLensCoreTests/AppStoreTests.swift`

- [ ] **Step 1: Write failing tests for file-transcriber phase transitions**

```swift
@MainActor
func test_beginFileTranscriptionMovesStateToProcessing() {
    let store = AppStore()
    let fileURL = URL(fileURLWithPath: "/tmp/demo.mp4")

    store.beginFileTranscription(for: fileURL)

    XCTAssertEqual(store.fileTranscription.phase, .processing)
    XCTAssertEqual(store.fileTranscription.selectedFileURL, fileURL)
}

@MainActor
func test_completeFileTranscriptionMovesStateToCompleted() {
    let store = AppStore()

    store.completeFileTranscription(lines: ["Line 1", "Line 2"])

    XCTAssertEqual(store.fileTranscription.phase, .completed)
    XCTAssertEqual(store.fileTranscription.completedLines, ["Line 1", "Line 2"])
}
```

- [ ] **Step 2: Run the focused test target to verify failure or partial failure**

Run: `xcodebuild test -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS' -only-testing:OhhLensTests/AppStoreTests`

Expected: FAIL until the file-transcriber implementation is complete.

- [ ] **Step 3: Expand the file transcription service to expose staged mock/demo progress**

```swift
public struct FileTranscriptionProgress: Equatable, Sendable {
    public var fractionCompleted: Double
    public var currentStep: String
}
```

```swift
public func demoProgressSequence(for request: FileTranscriptionRequest) -> [FileTranscriptionProgress] {
    [
        .init(fractionCompleted: 0.2, currentStep: "Extracting audio channel"),
        .init(fractionCompleted: 0.6, currentStep: "Running acoustic analysis"),
        .init(fractionCompleted: 0.9, currentStep: "Executing speaker diarization")
    ]
}
```

- [ ] **Step 4: Rebuild `FilesView` into the HTML three-phase workflow**

```swift
switch appStore.fileTranscription.phase {
case .idle:
    fileDropZone
case .processing:
    processingCard
case .completed:
    resultCard
}
```

```swift
private var fileDropZone: some View {
    GlassCard {
        VStack(spacing: 14) {
            Image(systemName: "plus")
            Text("Drag and drop audio or video files here")
            Text("Supports MP3, WAV, M4A, MP4, MKV")
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
```

- [ ] **Step 5: Wire a simple local completion flow for previewable results**

```swift
public func loadDemoFileTranscript() {
    fileTranscription.phase = .completed
    fileTranscription.progress = 1
    fileTranscription.completedLines = [
        "Alright, so I've been using this local transcription model for about two weeks now.",
        "And honestly, the speed is absolutely incredible because everything runs directly on-device."
    ]
}
```

- [ ] **Step 6: Run tests and build**

Run: `xcodebuild test -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS' -only-testing:OhhLensTests/AppStoreTests`

Expected: PASS.

Run: `xcodebuild build -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Sources/OhhLensApp/Views/FilesView.swift \
  Sources/OhhLensCore/Stores/AppStore.swift \
  Sources/OhhLensCore/Services/Capture/FileTranscriptionService.swift \
  Tests/OhhLensCoreTests/AppStoreTests.swift
git commit -m "feat: add html-matched file transcriber screen"
```

---

### Task 5: Implement Saved Transcripts and App Settings Screens

**Files:**
- Modify: `Sources/OhhLensApp/Views/HistoryView.swift`
- Modify: `Sources/OhhLensApp/Views/SetupView.swift`
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`
- Test: `Tests/OhhLensCoreTests/AppStoreTests.swift`

- [ ] **Step 1: Write failing tests for history selection and settings tab state**

```swift
@MainActor
func test_selectHistorySessionUpdatesViewerState() {
    let store = AppStore()
    store.applyPreviewTranscript()

    let sessionID = try XCTUnwrap(store.history.first?.id)
    store.selectHistorySession(sessionID)

    XCTAssertEqual(store.historyViewer.selectedSessionID, sessionID)
}
```

- [ ] **Step 2: Run tests to verify failure if helpers are incomplete**

Run: `xcodebuild test -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS' -only-testing:OhhLensTests/AppStoreTests`

Expected: FAIL until the selection helpers and screen bindings are wired.

- [ ] **Step 3: Rebuild `HistoryView` as the HTML two-pane archive**

```swift
HStack(spacing: 20) {
    historyListPane
        .frame(maxWidth: 320)

    historyViewerPane
        .frame(maxWidth: .infinity)
}
```

```swift
private var filteredHistory: [SessionRecord] {
    let query = appStore.historyViewer.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.isEmpty == false else { return appStore.history }
    return appStore.history.filter { session in
        session.segments.contains {
            ($0.originalText + " " + ($0.translatedText ?? "")).localizedCaseInsensitiveContains(query)
        }
    }
}
```

- [ ] **Step 4: Rebuild `SetupView` as the HTML `App Settings` panel**

```swift
VStack(alignment: .leading, spacing: 20) {
    Text("Settings")
        .font(.system(size: 24, weight: .bold))

    GlassCard {
        settingsGroup(
            title: "Audio & Transcription Model",
            rows: audioRows
        )
    }

    GlassCard {
        settingsGroup(
            title: "Subtitles Layout & Styling",
            rows: appearanceRows
        )
    }
}
```

- [ ] **Step 5: Bind settings rows to existing store-backed setup data**

```swift
private var audioRows: some View {
    VStack(spacing: 14) {
        settingsRow("Loopback Device", detail: appStore.selectedLoopbackDeviceName() ?? "None")
        settingsRow("Backend Service", detail: appStore.backendStatusText)
        settingsRow("Diagnostics", detail: appStore.setupMessage)
    }
}
```

- [ ] **Step 6: Run tests and build**

Run: `xcodebuild test -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS' -only-testing:OhhLensTests/AppStoreTests`

Expected: PASS.

Run: `xcodebuild build -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Sources/OhhLensApp/Views/HistoryView.swift \
  Sources/OhhLensApp/Views/SetupView.swift \
  Sources/OhhLensCore/Stores/AppStore.swift \
  Tests/OhhLensCoreTests/AppStoreTests.swift
git commit -m "feat: implement html-matched history and settings views"
```

---

### Task 6: Match the Native PiP Overlay to the HTML and Finish Verification

**Files:**
- Modify: `Sources/OhhLensCore/Services/Overlay/OverlayWindowController.swift`
- Modify: `Sources/OhhLensApp/Views/LiveView.swift`
- Modify: `Sources/OhhLensApp/Views/ConversationsView.swift`
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`
- Test: `xcodebuild build -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS'`

- [ ] **Step 1: Write the failing PiP state test**

```swift
@MainActor
func test_togglePiPDoesNotClearVisibleCaptionLines() {
    let store = AppStore()
    store.handleStreamingEvent(.final("The latest subtitle line"))

    store.togglePiP()

    XCTAssertEqual(store.liveTranscriptState.visibleCaptionLines.last, "The latest subtitle line")
    XCTAssertTrue(store.pipState.isVisible)
}
```

- [ ] **Step 2: Run tests to verify the PiP contract**

Run: `xcodebuild test -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS' -only-testing:OhhLensTests/AppStoreTests`

Expected: PASS or fail only on missing PiP behavior changes introduced in this task.

- [ ] **Step 3: Extend the overlay controller with update and dismiss behavior**

```swift
public func dismiss() {
    window?.orderOut(nil)
}

public func update<Content: View>(@ViewBuilder content: () -> Content) {
    present(content: content)
}
```

- [ ] **Step 4: Add an HTML-matched PiP presenter from the live screens**

```swift
private func syncPiP() {
    if appStore.pipState.isVisible {
        overlayController.update {
            PiPOverlayView(
                lines: appStore.liveTranscriptState.visibleCaptionLines,
                fontSize: appStore.pipState.fontSize,
                opacity: appStore.pipState.opacity
            )
        }
    } else {
        overlayController.dismiss()
    }
}
```

- [ ] **Step 5: Run full verification**

Run: `xcodebuild build -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED.

Run: `xcodebuild test -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS'`

Expected: TEST SUCCEEDED.

Run: `script/build_and_run.sh`

Expected: App launches and shows the HTML-matched five-tab shell. Confirm manually:
- `Live Subtitles` and `Conversations` switch correctly
- `File Transcriber` shows idle, processing, and result states
- `Saved Transcripts` shows two-pane archive layout
- `App Settings` shows backend/setup rows
- PiP opens from both live tabs and updates visible caption text

- [ ] **Step 6: Commit**

```bash
git add Sources/OhhLensCore/Services/Overlay/OverlayWindowController.swift \
  Sources/OhhLensApp/Views/LiveView.swift \
  Sources/OhhLensApp/Views/ConversationsView.swift \
  Sources/OhhLensCore/Stores/AppStore.swift
git commit -m "feat: finish html-matched pip and verification pass"
```

---

## Self-Review

### Spec coverage

- App shell replacement: covered by Task 1 and Task 2.
- Five-tab HTML structure: covered by Task 1 and Task 2.
- `Live Subtitles` and `Conversations`: covered by Task 3.
- `File Transcriber`: covered by Task 4.
- `Saved Transcripts`: covered by Task 5.
- `App Settings`: covered by Task 5.
- Native PiP overlay: covered by Task 6.
- Verification and exception reporting: covered by Task 6.

### Placeholder scan

- No `TODO`, `TBD`, or “implement later” placeholders remain.
- Each task names exact files and concrete commands.
- Code-bearing steps include concrete Swift or shell snippets.

### Type consistency

- `AppSection` consistently uses `liveSubtitles`, `conversations`, `fileTranscriber`, `savedTranscripts`, and `appSettings`.
- `AppStore` UI state consistently uses `fileTranscription`, `historyViewer`, and `pipState`.
- PiP flow consistently uses `togglePiP()`, `OverlayWindowController.update`, and `OverlayWindowController.dismiss`.
