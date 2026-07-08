# Live Subtitle Translation Design

## Summary

Add real-time English to Vietnamese translation to the existing live subtitle flow without slowing down raw subtitle display. The macOS app should keep rendering tiny English partials immediately, while the backend quietly assembles short stable English chunks, restores punctuation for translation quality, translates those chunks, and sends translation updates that the UI attaches beneath the current live English block.

## Why This Structure

The live socket already emits small text fragments, not sentence-ready subtitle rows. Treating each socket message as a full UI row would create noisy layout and mismatched translation updates. This slice keeps one responsibility per layer:

- backend owns chunk assembly, punctuation restoration, translation timing, and segment identity
- app state owns concatenating live English partials into the current visible subtitle block
- views render one active English line with one attached Vietnamese line

That keeps the UI fast while avoiding hallucinated or stale bilingual pairs.

## Goals

- Keep raw English live subtitles fast and visible with the current streaming feel.
- Support one fixed translation pair for v1: `English -> Vietnamese`.
- Require English as the source language for translation in v1.
- Add backend-owned punctuation restoration before translation.
- Emit short translated chunks instead of waiting for long full sentences.
- Render Vietnamese in the current live subtitle card without adding a separate side panel.
- Avoid mismatched English and Vietnamese when translations arrive late.

## Non-Goals

- Replacing the visible English subtitle text with punctuated English in v1.
- Multi-language source detection in live mode.
- Arbitrary translation target selection in the live subtitle path.
- Rolling bilingual subtitle history inside the live caption card.
- Full sentence-perfect segmentation or subtitle timing parity with offline transcription.

## Current Code Context

Relevant files today:

- `Sources/OhhLensCore/Stores/AppStore.swift`
  - consumes `partial` and `final` streaming events
  - appends finalized transcript content into History
- `Sources/OhhLensApp/Views/Shared/TranscriptWidgets.swift`
  - renders the current `Caption Stream` card
  - currently expects visible caption lines that are plain text only
- `Sources/OhhLensCore/Models/TranscriptSegment.swift`
  - already supports `translatedText` for saved transcript/history flows
- `backend/ohh-lens-speech-server/app/api/ws.py`
  - owns the live transcription socket protocol
- `backend/ohh-lens-speech-server/app/funasr/adapter.py`
  - already contains the streaming ASR integration and partial suppression work

This means the translation slice should extend the current live WebSocket protocol and app state rather than inventing a second live channel.

## Recommended Architecture

### 1. Raw English Live Path Stays Immediate

The existing ASR partial path remains the fast path.

Responsibilities:

- backend keeps emitting raw English partial events quickly
- app keeps concatenating partial text into the current visible English live buffer
- UI renders that English buffer immediately in the existing `Caption Stream` panel

This is the user’s low-latency line. Translation must not block it.

### 2. Backend Builds Short Translation Segments

The backend maintains a short sentence-candidate buffer separate from the raw partial stream.

Responsibilities:

- collect stable/finalized English fragments into the current translation candidate
- run punctuation restoration on that buffered English text
- decide when the candidate is ready to translate
- assign one backend-generated `segment_id` to that candidate

The translation candidate flushes when the first of these happens:

- punctuation restoration indicates a strong sentence boundary
- buffered English reaches about `10` words
- buffered English represents about `2.0` seconds of finalized speech

This hybrid rule prevents waiting for long sentences while still improving translation quality over fragment-by-fragment translation.

### 3. Punctuation Restoration Is Backend-Only for v1

Use a punctuation restoration model such as `ct-punc` inside the backend before translation.

Responsibilities:

- accept assembled English candidate text
- restore punctuation for translation quality
- keep punctuated English internal to the backend in v1

The app should not replace already-rendered raw English with punctuated English in this slice. Raw English remains the visible live subtitle text for simplicity and stability.

### 4. Translation Service Layer

Add a translation step in the backend after punctuation restoration.

Responsibilities:

- accept punctuated English text only
- translate from English to Vietnamese only in v1
- return translated text plus the source segment metadata needed by the app

The translation service may be local-model based, but this design does not lock the implementation to a specific model yet. The contract matters more than the provider at this stage.

### 5. UI Shows One Active English Block With One Attached Vietnamese Line

The live subtitle card keeps a single-column reading flow.

Layout rules:

- no separate right-side translation panel
- one large English line as the primary content
- one smaller Vietnamese line directly underneath it
- Vietnamese can lag English by roughly `1` to `2` seconds

This preserves the current reading pattern while making translation feel attached to the same spoken idea.

## Data Flow

1. Audio streams to the backend as it does today.
2. Backend ASR emits small English partial text updates.
3. App concatenates those partials into one current visible English live buffer.
4. In parallel, backend accumulates stable/finalized English into a translation candidate buffer.
5. Backend runs punctuation restoration on the candidate.
6. Backend flushes the candidate when a strong boundary, word cap, or time cap is reached.
7. Backend translates that flushed candidate from English to Vietnamese.
8. Backend emits a translation event with the translated text and the `segment_id`.
9. App matches the translation event to the active live subtitle segment and updates the Vietnamese line under the English line.

## WebSocket Event Shape

Use one websocket with explicit event types rather than asking the client to infer meaning.

Suggested event examples:

```json
{ "type": "partial", "segment_id": "seg_12", "text": "i want to review" }
{ "type": "partial", "segment_id": "seg_12", "text": "this page" }
{ "type": "translation", "segment_id": "seg_12", "source_text": "i want to review this page", "translated_text": "toi muon xem lai trang nay" }
```

Rules:

- `partial` events feed the current English live buffer
- `translation` events update only the Vietnamese line
- backend switches to a new `segment_id` when a new translation-worthy chunk begins

The `segment_id` is required so the UI can ignore stale translation events and clear the old Vietnamese line when the English segment changes.

## App State Model

The app should treat live translation as one active mutable subtitle pair, not as a growing list of fragment rows.

Suggested live state:

- `activeSegmentId`
- `englishBuffer`
- `vietnameseText`

Behavior:

- on `partial` with the current `segment_id`, append or merge into `englishBuffer`
- on `partial` with a new `segment_id`, reset `englishBuffer` and clear `vietnameseText`
- on `translation` for the active `segment_id`, update `vietnameseText`
- on `translation` for an older `segment_id`, ignore it

This keeps the live UI stable even when translation arrives after the English has moved on.

## UX Rules

### Live Card Behavior

- English remains the large primary line.
- Vietnamese remains visually secondary.
- If translation is not ready yet, show only English.
- When a translation arrives, fill the Vietnamese line under the current English block.
- When a clearly new English segment starts, clear the old Vietnamese line immediately.

### Why Not a Second Panel

A separate translation panel would force horizontal eye movement during live listening. The single-column stacked layout keeps both languages attached to the same spoken moment and is easier to scan under time pressure.

## Error Handling

### Translation Delay

If translation is slower than subtitle generation:

- keep English live subtitles flowing
- leave Vietnamese empty until the matching translation arrives
- do not freeze or delay the English UI

### Late Translation

If a translation arrives for an older `segment_id`:

- ignore it in the live card
- do not replace the current Vietnamese line with stale content

### Translation Failure

If translation fails for one segment:

- continue streaming English normally
- leave Vietnamese empty for that segment
- do not fail the whole socket session just because translation failed

### Reconnect

On socket reconnect:

- clear `activeSegmentId`
- clear `englishBuffer`
- clear `vietnameseText`

This prevents stale bilingual text from lingering after disconnect/reconnect cycles.

## Testing Strategy

### Backend Tests

Add or extend tests for:

- translation candidate buffering across multiple English fragments
- flush on strong punctuation boundary
- flush on word-count cap
- flush on time cap
- translation event payload shape including `segment_id`
- late or failed translation not breaking English subtitle flow

### App/Core Tests

Add or extend tests for:

- partials with the same `segment_id` concatenate into one visible English buffer
- changing `segment_id` resets the live subtitle pair
- translation updates the Vietnamese line only when ids match
- late translation for an older segment is ignored
- reconnect clears stale subtitle state

### UI Tests

Verify the `Caption Stream` view can render:

- English only
- English plus Vietnamese
- cleared Vietnamese when a new segment starts
- error text without breaking the live subtitle layout

## History Persistence Decision

Saved History sessions remain English-only for this slice, even when live Vietnamese translation is enabled.

Reason:

- it keeps the first live translation slice focused on the live UX and websocket contract
- it avoids mixing a new persistence model into the same change
- the project already has translation support in offline/history-oriented flows, so live-persisted translation can be handled as a follow-up slice if needed

## Open Implementation Decisions

These are intentionally deferred to the implementation plan:

- exact backend translation model/provider
- whether translation runs inline in the ASR worker or through a dedicated service object

## Recommended Slice Order

1. Extend backend live event model with `segment_id` and `translation` events.
2. Add backend sentence-candidate buffering plus punctuation restoration.
3. Add English to Vietnamese translation in the backend.
4. Extend app/core streaming state to track the active bilingual subtitle pair.
5. Update the live subtitle card to render the secondary Vietnamese line.
6. Add focused backend and app tests for segment matching and stale-update handling.
