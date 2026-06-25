# Ohh Lens Speech Server Design

## Summary

Build a new standalone local backend service for Ohh Lens that accepts live audio from the macOS app over WebSocket and returns low-latency transcription updates. The backend will import FunASR as a dependency instead of modifying the upstream FunASR server. The first version supports transcription only, not translation.

## Goals

- Provide a stable local backend contract for the Ohh Lens macOS app.
- Support true streaming input over WebSocket using raw PCM audio chunks.
- Emit both partial updates and finalized transcript segments.
- Keep FunASR integration isolated behind a backend adapter layer.
- Make the backend easy to run on a user’s machine with explicit local setup instructions.

## Non-Goals

- Translation in the first version.
- Remote multi-user deployment.
- Browser authentication, accounts, or cloud sync.
- Modifying the existing upstream FunASR FastAPI server in-place.

## Product Shape

The new backend is a standalone Python project that runs locally on the same machine as Ohh Lens. The macOS app connects to it via WebSocket for live transcription and can also call simple HTTP health endpoints for readiness checks.

This project acts as a gateway:

- Ohh Lens sends `16 kHz`, mono, `PCM int16` audio frames.
- The gateway manages buffering and session state.
- The gateway feeds audio incrementally into FunASR.
- The gateway sends `partial` and `final` transcript events back to the app.

## Why A Standalone Service

This approach keeps the app-facing protocol under our control while avoiding deep changes to upstream FunASR. It gives us:

- a stable contract for the macOS client
- room to swap or upgrade FunASR internals later
- isolated testing of protocol, buffering, and session lifecycle
- simpler shipping documentation for local setup

## Existing Backend Findings

The current FunASR repo already includes a FastAPI server with file-upload endpoints:

- `POST /v1/audio/transcriptions`
- `POST /asr`
- `GET /health`

Those routes are file-based rather than WebSocket-based. The repo also exposes streaming-oriented inference hooks through FunASR model APIs such as `generate(..., cache=..., is_final=...)`. That means the new backend should build a thin streaming protocol layer on top of those incremental inference capabilities instead of wrapping the existing upload endpoints.

## Protocol

### WebSocket Endpoint

- `ws://127.0.0.1:<port>/ws/transcribe`

### Client To Server Messages

The client sends:

1. A JSON `start` message
2. Binary PCM chunks
3. A JSON `stop` message

Example:

```json
{
  "type": "start",
  "session_id": "uuid",
  "sample_rate": 16000,
  "channels": 1,
  "sample_format": "pcm_s16le",
  "language": "auto"
}
```

### Server To Client Messages

The server emits:

- `ready`
- `partial`
- `final`
- `error`
- `closed`

Example partial event:

```json
{
  "type": "partial",
  "session_id": "uuid",
  "text": "hello everyone",
  "start_ms": 0,
  "end_ms": 1680
}
```

### Protocol Rules

- The server must reject audio bytes before a valid `start` message.
- The audio format is fixed in v1: `16 kHz`, mono, `PCM int16`.
- The server may reject unsupported format metadata instead of attempting implicit conversion.
- `stop` triggers a final flush into FunASR with `is_final=true`.
- Each WebSocket connection owns exactly one live transcription session.

## Audio Format

The app/backend wire format is:

- sample rate: `16000`
- channels: `1`
- encoding: signed `int16`
- byte order: little endian

This format is chosen because it is compact, ASR-friendly, and well-suited to low-latency speech streaming. Higher fidelity source audio such as routed YouTube playback can be downmixed and resampled on the macOS side before transmission.

## Architecture

### 1. FastAPI App

Owns:

- WebSocket route
- health route
- startup/shutdown hooks
- dependency wiring

### 2. Session Manager

Tracks:

- active sessions by `session_id`
- connection lifecycle
- session start and stop transitions
- cleanup on disconnect or failure

Each session stores:

- protocol metadata
- rolling PCM buffer
- FunASR cache/state
- current transcript state

### 3. Audio Stream Buffer

Accepts incoming PCM bytes and slices them into inference-sized windows. It must support:

- append bytes
- detect complete frames
- yield chunk windows
- flush remainder on finalization

The buffer should be deterministic and independent from WebSocket code so it is easy to unit test.

### 4. FunASR Streaming Adapter

This is the backend boundary around FunASR internals. It translates backend session operations into FunASR incremental inference calls using cache-based streaming APIs. It is responsible for:

- model loading
- per-session cache initialization
- incremental inference calls
- final flush behavior
- normalization of raw model output

This adapter must hide FunASR-specific details from the WebSocket layer.

### 5. Transcript Emitter

Transforms adapter results into normalized app-facing events:

- partial text updates while speech is still in flight
- finalized segments when the model stabilizes or the stream ends

It also normalizes event shape so the macOS client never needs to understand raw FunASR result structures.

## Inference Flow

1. The app opens `/ws/transcribe`.
2. The app sends a `start` message.
3. The backend validates metadata and creates session state.
4. The backend responds with `ready`.
5. The app streams binary PCM chunks.
6. The backend appends bytes into the session buffer.
7. When enough audio accumulates, the backend calls the FunASR adapter with:
   - current PCM chunk
   - current session cache
   - `is_final=false`
8. The adapter returns normalized incremental results.
9. The backend emits `partial` and, when available, `final` events.
10. When the app sends `stop`, the backend flushes the remaining audio with `is_final=true`.
11. The backend emits final transcript events and then `closed`.

## Error Handling

### Startup Errors

- If FunASR models fail to load, the health endpoint must report unhealthy.
- The WebSocket route should reject new sessions if the backend is not ready.

### Protocol Errors

- Invalid JSON message type -> send `error`, close connection.
- Unsupported audio metadata -> send `error`, close connection.
- Audio sent before `start` -> send `error`, close connection.

### Runtime Errors

- FunASR inference exception -> send `error`, release session state, close connection.
- Unexpected disconnect -> clean up session immediately.
- Empty or silent stream -> keep the session open until timeout or `stop`, then close cleanly.

### Separation Of State

The backend should preserve separate ideas of:

- connection state
- audio flow state
- transcription state

This matches the macOS app’s need to report “audio detected” separately from “backend connected.”

## Health And Diagnostics

HTTP endpoints:

- `GET /health`
- `GET /ready` optional if we want a stricter readiness check later

The health response should expose:

- backend status
- FunASR load status
- model name
- sample format expectations

This gives the app enough information to show setup diagnostics without probing the WebSocket endpoint directly.

## Project Layout

Suggested new project root:

- `backend/ohh-lens-speech-server/`

Suggested structure:

```text
backend/ohh-lens-speech-server/
  app/
    main.py
    api/
      health.py
      ws.py
    core/
      config.py
      protocol.py
      session_manager.py
    audio/
      buffer.py
    funasr/
      adapter.py
      models.py
  tests/
    test_buffer.py
    test_health.py
    test_protocol.py
    test_ws_flow.py
  pyproject.toml
  README.md
```

## Testing Strategy

### Unit Tests

- protocol validation for `start` and `stop`
- PCM buffering and chunk extraction
- transcript event normalization
- session cleanup behavior

### Integration Tests

- WebSocket happy path
- invalid protocol message handling
- stop-and-final-flush behavior
- disconnect cleanup

### Adapter Tests

Use a fake or stub streaming engine first so protocol tests do not depend on live model inference. Real FunASR integration can then be smoke-tested separately.

## Operational Expectations

The backend is expected to run locally on the user’s computer. The initial shipping story is:

- user installs Python dependencies
- user runs the speech server locally
- Ohh Lens connects to `127.0.0.1`

Later, we can improve this with bundled launch scripts, service wrappers, or an embedded runtime, but the first version should prioritize reliability and observability.

## Open Decisions Resolved

- project type: standalone backend service
- transport: WebSocket
- audio format: `16 kHz` mono `PCM int16`
- transcript output: partial plus finalized segments
- translation: deferred to a later phase

## Implementation Notes

The first implementation should prioritize protocol correctness and session lifecycle over optimization. Buffer sizing and chunk cadence can be tuned after the baseline path works. If FunASR’s true incremental interface proves inconsistent in practice, the adapter is the only place allowed to absorb that complexity; the client protocol must stay stable.
