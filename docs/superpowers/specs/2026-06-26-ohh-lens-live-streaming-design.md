# Ohh Lens Live Streaming Design

## Summary

Implement live subtitle streaming from the macOS app to the local FunASR backend by extending the existing loopback capture path. The app should stream PCM audio chunks over the backend WebSocket, show partial and final subtitles in real time, persist completed transcripts into History, and surface reconnect or backend failure states clearly in the UI.

## Why This Structure

This slice is organized around one responsibility per layer so the code stays understandable:

- capture code produces audio
- streaming code speaks WebSocket to the backend
- app state coordinates lifecycle and persistence
- views render current state

That separation makes it easier to debug:

- if audio is missing, inspect capture
- if partials are missing, inspect WebSocket flow
- if text is present but not saved, inspect `AppStore`

## Goals

- Stream live system audio from the macOS app into the backend WebSocket.
- Use the backend protocol already implemented at `ws://127.0.0.1:8765/ws/transcribe`.
- Show partial transcript updates while audio is still flowing.
- Save finalized transcript segments into History when a listening session ends cleanly.
- Surface backend disconnects and startup failures without pretending subtitles are still live.

## Non-Goals

- Translation generation in this slice.
- File-import transcription in this slice.
- Multi-session background queueing.
- Speaker diarization or timestamp-perfect subtitle rendering.

## Current Code Context

Relevant files today:

- `Sources/OhhLensCore/Services/Capture/LoopbackCaptureService.swift`
  - already captures loopback audio and computes audio-level snapshots
- `Sources/OhhLensCore/Services/FunASRClient.swift`
  - currently only performs a `/health` check
- `Sources/OhhLensCore/Stores/AppStore.swift`
  - owns listening state, setup state, history state, and loopback capture orchestration
- `Sources/OhhLensApp/Views/LiveView.swift`
  - already shows listening state, backend summary, and current session messaging

This means the right move is to add a streaming client and raw-audio callback seam instead of collapsing everything into one new service.

## Recommended Architecture

### 1. Capture Layer

Extend `LoopbackCaptureService` so it can emit raw PCM audio chunks in addition to level updates.

Responsibilities:

- keep using `AVCaptureAudioDataOutput`
- continue publishing `AudioLevelSnapshot`
- convert audio sample buffers into backend-compatible mono `pcm_s16le`
- emit binary audio chunks through a new callback

Constraints:

- chunk production should stay lightweight and non-blocking
- if a sample buffer cannot be converted, skip that buffer instead of crashing the session

### 2. Streaming Layer

Add a dedicated WebSocket client service for FunASR live transcription.

Suggested file:

- `Sources/OhhLensCore/Services/FunASRStreamingClient.swift`

Responsibilities:

- connect to `ws://127.0.0.1:8765/ws/transcribe`
- send the backend `start` message
- stream binary PCM chunks as they arrive
- send the backend `stop` message on shutdown
- receive `ready`, `partial`, `final`, `error`, and `closed` events
- map raw backend messages into typed Swift events

The service should not know about SwiftUI, History, or the selected UI caption mode.

### 3. App State Layer

Enhance `AppStore` so it coordinates one active live transcription session.

Responsibilities:

- gate listening on backend readiness and loopback availability
- create and own the capture service plus streaming client
- append incoming partial text to a “live transcript” field
- collect final transcript segments in memory during the current session
- persist a `SessionRecord` into History when the session ends with transcript data
- update `statusText`, `backendStatusText`, and setup messaging on failures

This is the main learning boundary:

- `LoopbackCaptureService` knows audio
- `FunASRStreamingClient` knows protocol
- `AppStore` knows product behavior

### 4. UI Layer

Update `LiveView` to render:

- current partial transcript
- last finalized text
- clearer backend/session status
- recovery messaging when the backend disconnects or returns an error

The view should remain a thin renderer over `AppStore`.

## Data Flow

1. User presses `Start Listening`.
2. `AppStore` verifies the source, selected loopback device, and backend availability.
3. `AppStore` creates a `FunASRStreamingClient` and opens a WebSocket session.
4. `AppStore` starts `LoopbackCaptureService`.
5. `LoopbackCaptureService` emits:
   - level updates for UI feedback
   - PCM chunks for backend streaming
6. `FunASRStreamingClient` sends:
   - one `start` message
   - repeated binary PCM chunks
   - one `stop` message on shutdown
7. Backend emits:
   - `ready`
   - `partial`
   - `final`
   - `error`
   - `closed`
8. `AppStore` updates UI state and stores final transcript segments.
9. On stop or clean close, `AppStore` persists a completed `SessionRecord` if any final transcript exists.

## Audio Format Rules

The backend expects:

- `16000 Hz`
- mono
- `pcm_s16le`

The macOS capture path may not naturally arrive in that exact shape, so capture conversion logic must normalize the sample buffer before sending.

This slice does not need a general-purpose audio resampler abstraction if a focused conversion path is enough for the devices we are already capturing from.

## Session State Model

Add explicit session-facing state in `AppStore`, for example:

- idle
- connecting
- streaming
- degraded
- stopping

Also track:

- current partial transcript text
- finalized transcript text or segments for the current session
- last stream error message

This avoids overloading `statusText` with every concern.

## Error Handling

### Startup Errors

If the backend health check fails before streaming starts:

- do not begin listening
- set backend/session status to a user-facing failure message
- keep the app responsive so the user can retry

### WebSocket Errors

If the socket errors mid-session:

- stop forwarding audio
- stop the capture service
- mark the session degraded
- keep any final transcript segments already received
- do not silently restart in the background for this first slice

### Stop Behavior

When the user presses `Stop`:

- stop capture
- send `stop` to backend
- wait briefly for final events if needed
- persist a `SessionRecord` only when transcript content exists

## Persistence Rules

Persist only finalized transcript content.

Do not save:

- partial transcript-only sessions
- empty sessions
- backend error payloads as fake transcript text

The saved session should continue using the existing `SessionRecord` and `TranscriptSegment` path rather than inventing a second history model.

## Testing Strategy

### Unit Tests

Extend or add tests for:

- `FunASRStreamingClient` message parsing and send flow
- `AppStore` start/stop lifecycle
- partial transcript updates
- final transcript accumulation
- session persistence on successful stop
- degraded state on backend disconnect or backend error

### Capture Tests

Keep the existing loopback level tests.

Add focused tests only for the new raw-audio callback seam and conversion helpers where practical.

### Verification

After implementation:

- run the relevant Swift tests
- run the full package tests
- run the backend and app together for one manual smoke test

## Teaching Notes

The structure to pay attention to while reading the code later:

1. Start from the product behavior in `AppStore`.
2. Follow the outbound audio path into `LoopbackCaptureService`.
3. Follow the network boundary into `FunASRStreamingClient`.
4. Follow inbound transcript events back into `AppStore`.
5. Only then read the SwiftUI view updates.

That order mirrors the control flow and is the fastest way to understand the feature without getting lost in implementation detail.
