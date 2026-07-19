# Live Subtitle Translation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add live English-to-Vietnamese subtitle translation without delaying the existing fast English streaming path.

**Architecture:** The backend remains the source of truth for live segment boundaries, punctuation restoration, and translation timing. The Swift app continues rendering raw English partials immediately, but now tracks one active bilingual subtitle pair keyed by backend `segment_id` so translation can appear underneath the current English line without mismatches.

**Tech Stack:** FastAPI, Python session/state helpers, FunASR streaming adapter, Swift, SwiftUI, XCTest, pytest

## Global Constraints

- Keep raw English live subtitles fast and visible with the current streaming feel.
- Support one fixed translation pair for v1: `English -> Vietnamese`.
- Require English as the source language for translation in v1.
- Add backend-owned punctuation restoration before translation.
- Emit short translated chunks instead of waiting for long full sentences.
- Render Vietnamese in the current live subtitle card without adding a separate side panel.
- Avoid mismatched English and Vietnamese when translations arrive late.
- Do not replace the visible English subtitle text with punctuated English in v1.
- Saved History sessions remain English-only for this slice, even when live Vietnamese translation is enabled.

---

## File Structure

- Modify `backend/ohh-lens-speech-server/app/core/session_manager.py`
  - add per-session translation segment buffering, `segment_id` assignment, and translation event emission
- Create `backend/ohh-lens-speech-server/app/core/live_translation.py`
  - isolate punctuation/translation candidate logic from websocket handling
- Modify `backend/ohh-lens-speech-server/app/api/ws.py`
  - keep websocket transport thin while forwarding new `translation` payloads
- Modify `backend/ohh-lens-speech-server/tests/test_ws_flow.py`
  - cover new websocket event shape and stale-segment behavior
- Modify `Sources/OhhLensCore/Services/FunASRClient.swift`
  - add typed streaming events carrying `segmentID`
- Modify `Sources/OhhLensCore/Services/FunASRStreamingClient.swift`
  - decode `translation` payloads and segment-aware partials
- Modify `Sources/OhhLensCore/Models/LiveTranscriptState.swift`
  - store one active bilingual live subtitle pair
- Modify `Sources/OhhLensCore/Stores/AppStore.swift`
  - apply segment-aware streaming events and clear stale Vietnamese when a new segment starts
- Modify `Sources/OhhLensApp/Views/Shared/TranscriptWidgets.swift`
  - render Vietnamese beneath the current English line in the existing caption card
- Modify `Tests/OhhLensCoreTests/FunASRStreamingClientTests.swift`
  - verify event decoding for `segment_id` and `translation`
- Modify `Tests/OhhLensCoreTests/AppStoreTests.swift`
  - verify state transitions for segment changes and translation arrival

### Task 1: Extend Backend WebSocket Events With `segment_id`

**Files:**
- Modify: `backend/ohh-lens-speech-server/app/core/session_manager.py`
- Modify: `backend/ohh-lens-speech-server/app/api/ws.py`
- Test: `backend/ohh-lens-speech-server/tests/test_ws_flow.py`

**Interfaces:**
- Consumes: existing `SessionManager.start_session(session_id: str, start: StartMessage) -> None`
- Produces: `SessionManager.push_audio(session_id: str, chunk: bytes) -> list[dict[str, object]]` where every emitted `partial` and `final` payload includes `"segment_id": str`

- [ ] **Step 1: Write the failing backend websocket tests**

```python
def test_ws_transcribe_partials_include_segment_id():
    client = TestClient(create_app(adapter=FakeStreamingAdapter()))

    with client.websocket_connect("/ws/transcribe") as websocket:
        websocket.send_json(
            {
                "type": "start",
                "session_id": "segment-session",
                "sample_rate": 16000,
                "channels": 1,
                "sample_format": "pcm_s16le",
                "language": "en",
            }
        )
        assert websocket.receive_json()["type"] == "ready"

        websocket.send_bytes(b"\x00\x01" * 32000)
        event = websocket.receive_json()

        assert event["type"] == "partial"
        assert event["segment_id"] == "segment-session-1"
        assert event["text"] == "partial text"


def test_ws_transcribe_final_includes_segment_id():
    client = TestClient(create_app(adapter=FakeStreamingAdapter()))

    with client.websocket_connect("/ws/transcribe") as websocket:
        websocket.send_json(
            {
                "type": "start",
                "session_id": "segment-final",
                "sample_rate": 16000,
                "channels": 1,
                "sample_format": "pcm_s16le",
                "language": "en",
            }
        )
        assert websocket.receive_json()["type"] == "ready"

        websocket.send_bytes(b"\x00\x01" * 32000)
        _ = [websocket.receive_json() for _ in range(3)]
        websocket.send_json({"type": "stop"})

        final_event = websocket.receive_json()

        assert final_event == {
            "type": "final",
            "segment_id": "segment-final-1",
            "text": "final text",
        }
```

- [ ] **Step 2: Run the backend websocket tests and verify failure**

Run:

```bash
pytest /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server/tests/test_ws_flow.py -k "segment_id or includes_segment_id" -v
```

Expected: `FAIL` because emitted `partial` and `final` payloads do not yet contain `segment_id`.

- [ ] **Step 3: Implement minimal segment-aware websocket payloads**

```python
@dataclass
class LiveSessionState:
    start: StartMessage
    buffered_audio: bytearray = field(default_factory=bytearray)
    active_segment_index: int = 1

    @property
    def active_segment_id(self) -> str:
        return f"{self.start.session_id}-{self.active_segment_index}"


def _partial_event(self, state: LiveSessionState, text: str) -> dict[str, object]:
    return {
        "type": "partial",
        "segment_id": state.active_segment_id,
        "text": text,
    }


def _final_event(self, state: LiveSessionState, text: str) -> dict[str, object]:
    return {
        "type": "final",
        "segment_id": state.active_segment_id,
        "text": text,
    }
```

- [ ] **Step 4: Run the backend websocket tests and verify pass**

Run:

```bash
pytest /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server/tests/test_ws_flow.py -k "segment_id or includes_segment_id" -v
```

Expected: `PASS` with both new tests green.

- [ ] **Step 5: Commit backend segment-id event support**

```bash
git add backend/ohh-lens-speech-server/app/core/session_manager.py \
        backend/ohh-lens-speech-server/app/api/ws.py \
        backend/ohh-lens-speech-server/tests/test_ws_flow.py
git commit -m "feat: add segment ids to live subtitle events"
```

### Task 2: Add Backend Translation Candidate Buffering And `translation` Events

**Files:**
- Create: `backend/ohh-lens-speech-server/app/core/live_translation.py`
- Modify: `backend/ohh-lens-speech-server/app/core/session_manager.py`
- Test: `backend/ohh-lens-speech-server/tests/test_ws_flow.py`

**Interfaces:**
- Consumes: `LiveTranslationAssembler.push_final_text(segment_id: str, text: str) -> list[dict[str, object]]`
- Produces: translation websocket payloads shaped as `{"type": "translation", "segment_id": str, "source_text": str, "translated_text": str}`

- [ ] **Step 1: Write the failing translation-buffer tests**

```python
class StubTranslator:
    def punctuate(self, text: str) -> str:
        if text == "i want to review this page":
            return "I want to review this page."
        return text

    def translate(self, text: str) -> str:
        assert text == "I want to review this page."
        return "toi muon xem lai trang nay"


def test_session_manager_emits_translation_event_after_sentence_boundary():
    session_manager = SessionManager(
        adapter=FakeStreamingAdapter(),
        translator=StubTranslator(),
    )
    start = StartMessage(
        type="start",
        session_id="translate-session",
        sample_rate=16000,
        channels=1,
        sample_format="pcm_s16le",
        language="en",
    )

    session_manager.start_session("translate-session", start)

    translation_events = session_manager.push_final_text(
        "translate-session",
        segment_id="translate-session-1",
        text="i want to review this page",
    )

    assert translation_events == [
        {
            "type": "translation",
            "segment_id": "translate-session-1",
            "source_text": "i want to review this page",
            "translated_text": "toi muon xem lai trang nay",
        }
    ]


def test_session_manager_flushes_translation_when_word_cap_is_hit():
    translator = StubTranslator()
    assembler = LiveTranslationAssembler(
        translator=translator,
        word_cap=4,
        seconds_cap=2.0,
    )

    events = assembler.push_final_text(
        segment_id="seg-2",
        text="review this page with me",
    )

    assert events[0]["type"] == "translation"
    assert events[0]["segment_id"] == "seg-2"
```

- [ ] **Step 2: Run the translation-buffer tests and verify failure**

Run:

```bash
pytest /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server/tests/test_ws_flow.py -k "translation_event or word_cap" -v
```

Expected: `FAIL` because no translation assembler or `translation` event exists yet.

- [ ] **Step 3: Implement the minimal translation assembler**

```python
@dataclass
class LiveTranslationAssembler:
    translator: TranslatorProtocol
    word_cap: int = 10
    seconds_cap: float = 2.0
    pending_source_text: str = ""

    def push_final_text(self, segment_id: str, text: str) -> list[dict[str, object]]:
        incoming = " ".join(text.split()).strip()
        if not incoming:
            return []

        self.pending_source_text = " ".join(
            part for part in [self.pending_source_text, incoming] if part
        ).strip()
        punctuated = self.translator.punctuate(self.pending_source_text)

        if self._should_flush(punctuated):
            source_text = self.pending_source_text
            translated_text = self.translator.translate(punctuated)
            self.pending_source_text = ""
            return [
                {
                    "type": "translation",
                    "segment_id": segment_id,
                    "source_text": source_text,
                    "translated_text": translated_text,
                }
            ]

        return []

    def _should_flush(self, punctuated: str) -> bool:
        if punctuated.endswith((".", "!", "?")):
            return True
        return len(self.pending_source_text.split()) >= self.word_cap
```

- [ ] **Step 4: Run the translation-buffer tests and verify pass**

Run:

```bash
pytest /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server/tests/test_ws_flow.py -k "translation_event or word_cap" -v
```

Expected: `PASS` with translation event payloads matching the spec.

- [ ] **Step 5: Commit backend translation buffering**

```bash
git add backend/ohh-lens-speech-server/app/core/live_translation.py \
        backend/ohh-lens-speech-server/app/core/session_manager.py \
        backend/ohh-lens-speech-server/tests/test_ws_flow.py
git commit -m "feat: add live translation buffering events"
```

### Task 3: Decode Segment-Aware Streaming Events In Swift

**Files:**
- Modify: `Sources/OhhLensCore/Services/FunASRClient.swift`
- Modify: `Sources/OhhLensCore/Services/FunASRStreamingClient.swift`
- Test: `Tests/OhhLensCoreTests/FunASRStreamingClientTests.swift`

**Interfaces:**
- Consumes: websocket JSON messages shaped as `{"type":"partial","segment_id":"seg-1","text":"..."}` and `{"type":"translation","segment_id":"seg-1","source_text":"...","translated_text":"..."}`
- Produces: 
  - `FunASRStreamingEvent.partial(segmentID: String, text: String)`
  - `FunASRStreamingEvent.final(segmentID: String, text: String)`
  - `FunASRStreamingEvent.translation(segmentID: String, sourceText: String, translatedText: String)`

- [ ] **Step 1: Write the failing Swift decoding tests**

```swift
func test_mapsPartialEventPayloadWithSegmentID() throws {
    let event = try FunASRStreamingClient.decodeEvent(
        from: #"{"type":"partial","segment_id":"seg-1","text":"hello world"}"#.data(using: .utf8)!
    )

    XCTAssertEqual(event, .partial(segmentID: "seg-1", text: "hello world"))
}

func test_mapsTranslationEventPayload() throws {
    let event = try FunASRStreamingClient.decodeEvent(
        from: #"{"type":"translation","segment_id":"seg-1","source_text":"hello world","translated_text":"xin chao the gioi"}"#.data(using: .utf8)!
    )

    XCTAssertEqual(
        event,
        .translation(
            segmentID: "seg-1",
            sourceText: "hello world",
            translatedText: "xin chao the gioi"
        )
    )
}
```

- [ ] **Step 2: Run the Swift streaming-client tests and verify failure**

Run:

```bash
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FunASRStreamingClientTests -v'
```

Expected: `FAIL` because `FunASRStreamingEvent` does not yet carry `segmentID` or `translation`.

- [ ] **Step 3: Implement typed segment-aware event decoding**

```swift
public enum FunASRStreamingEvent: Equatable, Sendable {
    case ready
    case partial(segmentID: String, text: String)
    case final(segmentID: String, text: String)
    case translation(segmentID: String, sourceText: String, translatedText: String)
    case error(String)
    case closed
}

switch payload.type {
case "partial":
    return .partial(
        segmentID: payload.segmentID ?? "legacy-segment",
        text: payload.text ?? ""
    )
case "final":
    return .final(
        segmentID: payload.segmentID ?? "legacy-segment",
        text: payload.text ?? ""
    )
case "translation":
    return .translation(
        segmentID: payload.segmentID ?? "legacy-segment",
        sourceText: payload.sourceText ?? "",
        translatedText: payload.translatedText ?? ""
    )
default:
    throw StreamingClientError.unsupportedEventType(payload.type)
}
```

- [ ] **Step 4: Run the Swift streaming-client tests and verify pass**

Run:

```bash
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FunASRStreamingClientTests -v'
```

Expected: `PASS` with new `segment_id` and `translation` decoding coverage green.

- [ ] **Step 5: Commit Swift event decoding changes**

```bash
git add Sources/OhhLensCore/Services/FunASRClient.swift \
        Sources/OhhLensCore/Services/FunASRStreamingClient.swift \
        Tests/OhhLensCoreTests/FunASRStreamingClientTests.swift
git commit -m "feat: decode live translation streaming events"
```

### Task 4: Track One Active Bilingual Subtitle Pair In App State

**Files:**
- Modify: `Sources/OhhLensCore/Models/LiveTranscriptState.swift`
- Modify: `Sources/OhhLensCore/Stores/AppStore.swift`
- Test: `Tests/OhhLensCoreTests/AppStoreTests.swift`

**Interfaces:**
- Consumes:
  - `FunASRStreamingEvent.partial(segmentID:text:)`
  - `FunASRStreamingEvent.final(segmentID:text:)`
  - `FunASRStreamingEvent.translation(segmentID:sourceText:translatedText:)`
- Produces:
  - `LiveTranscriptState.activeSegmentID: String?`
  - `LiveTranscriptState.currentVietnameseText: String`
  - `LiveTranscriptState.visibleCaptionLines: [String]`
  - `LiveTranscriptState.visibleTranslationLine: String?`

- [ ] **Step 1: Write the failing AppStore state tests**

```swift
@MainActor
func test_translationUpdatesVietnameseForActiveSegment() {
    var state = LiveTranscriptState()
    state.applyPartial(segmentID: "seg-1", text: "i want to review")
    state.applyTranslation(
        segmentID: "seg-1",
        sourceText: "i want to review",
        translatedText: "toi muon xem lai"
    )

    XCTAssertEqual(state.visibleCaptionLines.last, "i want to review")
    XCTAssertEqual(state.visibleTranslationLine, "toi muon xem lai")
}

@MainActor
func test_newSegmentClearsOldVietnameseImmediately() {
    var state = LiveTranscriptState()
    state.applyPartial(segmentID: "seg-1", text: "i want to review")
    state.applyTranslation(
        segmentID: "seg-1",
        sourceText: "i want to review",
        translatedText: "toi muon xem lai"
    )

    state.applyPartial(segmentID: "seg-2", text: "update payment")

    XCTAssertEqual(state.visibleCaptionLines.last, "update payment")
    XCTAssertNil(state.visibleTranslationLine)
}
```

- [ ] **Step 2: Run the AppStore tests and verify failure**

Run:

```bash
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppStoreTests -v'
```

Expected: `FAIL` because `LiveTranscriptState` does not yet track `segmentID` or translation text.

- [ ] **Step 3: Implement minimal bilingual live state**

```swift
public struct LiveTranscriptState: Equatable, Sendable {
    public var activeSegmentID: String?
    public var partialText: String
    public var currentVietnameseText: String

    public var visibleTranslationLine: String? {
        let trimmed = currentVietnameseText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public mutating func applyPartial(segmentID: String, text: String) {
        if activeSegmentID != segmentID {
            activeSegmentID = segmentID
            partialText = ""
            currentVietnameseText = ""
        }

        let incomingText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if partialText.isEmpty || incomingText.hasPrefix(partialText) {
            partialText = incomingText
        } else if partialText.hasSuffix(incomingText) == false {
            partialText = "\(partialText) \(incomingText)".trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public mutating func applyTranslation(segmentID: String, sourceText: String, translatedText: String) {
        guard activeSegmentID == segmentID else { return }
        currentVietnameseText = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run the AppStore tests and verify pass**

Run:

```bash
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppStoreTests -v'
```

Expected: `PASS` with active-segment translation behavior covered.

- [ ] **Step 5: Commit the live bilingual state changes**

```bash
git add Sources/OhhLensCore/Models/LiveTranscriptState.swift \
        Sources/OhhLensCore/Stores/AppStore.swift \
        Tests/OhhLensCoreTests/AppStoreTests.swift
git commit -m "feat: track live subtitle translation state"
```

### Task 5: Render Vietnamese Under The Current English Subtitle

**Files:**
- Modify: `Sources/OhhLensApp/Views/Shared/TranscriptWidgets.swift`
- Modify: `Sources/OhhLensApp/Views/LiveView.swift`
- Test: `Tests/OhhLensCoreTests/AppStoreTests.swift`

**Interfaces:**
- Consumes:
  - `LiveCaptionViewport.visibleCaptionLines: [String]`
  - `LiveCaptionViewport.visibleTranslationLine: String?`
- Produces:
  - stacked live subtitle layout with one large English line and one smaller Vietnamese line underneath the newest English line

- [ ] **Step 1: Write the failing view-state assertion**

```swift
@MainActor
func test_liveTranscriptStateKeepsEnglishPrimaryAndVietnameseSecondary() {
    var state = LiveTranscriptState()
    state.applyPartial(segmentID: "seg-1", text: "i want to review this page")
    state.applyTranslation(
        segmentID: "seg-1",
        sourceText: "i want to review this page",
        translatedText: "toi muon xem lai trang nay"
    )

    XCTAssertEqual(state.visibleCaptionLines, ["i want to review this page"])
    XCTAssertEqual(state.visibleTranslationLine, "toi muon xem lai trang nay")
}
```

- [ ] **Step 2: Run the focused AppStore/live subtitle tests and verify failure**

Run:

```bash
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppStoreTests/test_liveTranscriptStateKeepsEnglishPrimaryAndVietnameseSecondary -v'
```

Expected: `FAIL` until the view model exposes a secondary translation line and the view accepts it.

- [ ] **Step 3: Implement the live caption layout update**

```swift
struct LiveCaptionViewport: View {
    let visibleCaptionLines: [String]
    let visibleTranslationLine: String?
    let isListening: Bool
    let idleMessage: String
    let lastError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // existing header

            if visibleCaptionLines.isEmpty {
                TranscriptIdleState(
                    title: "Live Subtitles Idle",
                    message: idleMessage
                )
            } else {
                ForEach(Array(visibleCaptionLines.enumerated()), id: \.offset) { index, line in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(index == visibleCaptionLines.count - 1 ? "Now" : "Previous")
                        Text(line)
                            .font(index == visibleCaptionLines.count - 1 ? .system(size: 28, weight: .semibold) : .system(size: 20, weight: .medium))

                        if index == visibleCaptionLines.count - 1, let visibleTranslationLine {
                            Text(visibleTranslationLine)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(AppTheme.ColorToken.textMuted)
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run the focused AppStore/live subtitle tests and verify pass**

Run:

```bash
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppStoreTests/test_liveTranscriptStateKeepsEnglishPrimaryAndVietnameseSecondary -v'
```

Expected: `PASS` with English staying primary and Vietnamese rendered as the secondary line.

- [ ] **Step 5: Commit the live subtitle UI update**

```bash
git add Sources/OhhLensApp/Views/Shared/TranscriptWidgets.swift \
        Sources/OhhLensApp/Views/LiveView.swift \
        Tests/OhhLensCoreTests/AppStoreTests.swift
git commit -m "feat: render translated live subtitle line"
```

### Task 6: Run The Full Verification Set

**Files:**
- Modify: `backend/ohh-lens-speech-server/tests/test_ws_flow.py` (only if final fixes are needed)
- Modify: `Tests/OhhLensCoreTests/FunASRStreamingClientTests.swift` (only if final fixes are needed)
- Modify: `Tests/OhhLensCoreTests/AppStoreTests.swift` (only if final fixes are needed)

**Interfaces:**
- Consumes: completed tasks 1 through 5
- Produces: green targeted backend and Swift test suites for the live translation slice

- [ ] **Step 1: Run the backend websocket suite**

Run:

```bash
pytest /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server/tests/test_ws_flow.py -v
```

Expected: `PASS` with segment-aware partial/final/translation event coverage.

- [ ] **Step 2: Run the Swift streaming client suite**

Run:

```bash
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FunASRStreamingClientTests -v'
```

Expected: `PASS` with translation event decoding covered.

- [ ] **Step 3: Run the Swift app-state suite**

Run:

```bash
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppStoreTests -v'
```

Expected: `PASS` with live translation state behavior covered.

- [ ] **Step 4: Fix any failing assertions with minimal edits and rerun the exact failing suite**

```bash
pytest /Users/steve/dev/personal/ohh-lens/backend/ohh-lens-speech-server/tests/test_ws_flow.py -v
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FunASRStreamingClientTests -v'
/bin/zsh -lc 'HOME=/Users/steve/dev/personal/ohh-lens/.home CLANG_MODULE_CACHE_PATH=/Users/steve/dev/personal/ohh-lens/.cache/clang/ModuleCache DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppStoreTests -v'
```

- [ ] **Step 5: Commit the verified slice**

```bash
git add backend/ohh-lens-speech-server/tests/test_ws_flow.py \
        Sources/OhhLensCore/Services/FunASRClient.swift \
        Sources/OhhLensCore/Services/FunASRStreamingClient.swift \
        Sources/OhhLensCore/Models/LiveTranscriptState.swift \
        Sources/OhhLensCore/Stores/AppStore.swift \
        Sources/OhhLensApp/Views/Shared/TranscriptWidgets.swift \
        Sources/OhhLensApp/Views/LiveView.swift \
        Tests/OhhLensCoreTests/FunASRStreamingClientTests.swift \
        Tests/OhhLensCoreTests/AppStoreTests.swift
git commit -m "feat: ship live subtitle translation"
```
