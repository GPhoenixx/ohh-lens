# System Audio Fallback Design

## Goal

Allow `System Audio` live transcription to remain usable for users who do not have a virtual audio device such as BlackHole installed. When routed loopback capture is unavailable, the app should fall back to microphone-based live capture instead of hard-failing. This change should reduce setup friction without hiding what capture path is actually in use.

## Scope

In scope:

- Add automatic fallback for `System Audio` when no loopback device is available.
- Keep `Microphone`, `System Audio`, `App Audio`, and file transcription as distinct source choices.
- Surface honest UI state that shows when `System Audio` is running through fallback.
- Update setup and idle messaging so the app no longer implies that all live capture requires a virtual device.
- Add focused store-level tests for source resolution and presentation state.

Out of scope:

- Changing `App Audio` to support fallback.
- Merging `Microphone` and `System Audio` into a single source.
- Rewriting the capture services or socket protocol.
- Adding a new settings toggle for fallback behavior.

## Product Decision Summary

- `System Audio` remains a visible source option.
- If a loopback device is available, `System Audio` behaves exactly as it does today.
- If no loopback device is available, `System Audio` falls back to microphone capture automatically.
- The fallback is presented to the user as `Live Audio`.
- `App Audio` continues to require a virtual device and should not silently degrade to microphone capture.

## Behavior

The app should preserve the user intent expressed by the selected source while resolving the best available capture path at start time.

### Start rules

1. If the user selects `Microphone`, start `MicrophoneCaptureService`.
2. If the user selects `System Audio` and a loopback device is available, start `LoopbackCaptureService(source: .systemAudio, deviceID: ...)`.
3. If the user selects `System Audio` and no loopback device is available, start `MicrophoneCaptureService`.
4. If the user selects `App Audio` and a loopback device is available, keep existing routed behavior.
5. If the user selects `App Audio` and no loopback device is available, do not start listening. Show clear guidance that app-audio isolation still requires a virtual device.

### Session meaning

- `selectedSource` continues to represent the source the user chose.
- The app also derives an effective capture path for the active session.
- Session history should preserve the intended source and record the resolved capture path for troubleshooting.

This lets the product remain honest about what the user asked for while still degrading gracefully when the routed path is unavailable.

## Architecture

The fallback decision should live in `AppStore`, not in the capture services.

### Why this boundary

- `MicrophoneCaptureService` should continue to mean microphone capture only.
- `LoopbackCaptureService` should continue to mean loopback capture only.
- Product-level degradation rules belong in orchestration code, where source selection, setup state, and UI state are already owned.

### Store responsibilities

`AppStore` should:

- inspect the selected source
- inspect loopback availability
- decide the effective capture path when listening starts
- expose small derived presentation state for the UI
- keep existing socket/session orchestration unchanged after the capture service is chosen

### Derived presentation state

Add a focused store-level derived state, `effectiveCaptureMode`, that describes the active or pending capture mode. It should cover these cases:

- direct microphone capture
- routed system audio capture
- system-audio fallback through microphone
- app-audio unavailable because loopback is missing

This derived state should drive header pills, idle text, setup descriptions, and status messaging. It should avoid scattering source + device-availability conditionals across multiple views.

## UI And Messaging

The UI should shift from a “missing dependency” experience to a “best available live capture” experience, while staying truthful.

### Live header

Current live headers show loopback-specific status for `System Audio` and `App Audio`. For this change:

- `System Audio` with loopback should continue to show routed-device selection.
- `System Audio` without loopback should show a clear fallback label such as `Live Audio`.
- `Microphone` can continue to show microphone-ready or microphone-live status.
- `App Audio` without loopback should show a blocked state that explains why it cannot start.

The key UI rule is that the fallback should look operational, not broken.

### Setup screen

`SetupView` should stop implying that all live capture depends on a loopback device. The loopback section should instead explain:

- a virtual device enables true routed system-audio capture
- `System Audio` can fall back to microphone-based live capture when the virtual device is missing
- `App Audio` still requires a virtual device for isolation

The loopback picker itself should remain available when devices are present, but the surrounding copy should read as a capability enhancer rather than a global blocker.

### Idle and empty-state copy

Idle copy in live transcript screens should become source-aware:

- `Microphone`: direct speech or live mic wording
- `System Audio` with loopback: routed system-audio wording
- `System Audio` fallback: live-audio wording that does not promise routed system capture
- `App Audio` unavailable: guidance that app audio still needs loopback routing

This change is important because the current “capture system-wide streaming audio” copy becomes misleading when fallback is active.

## Data Flow

The runtime flow should remain close to the existing implementation:

1. User chooses a source in the UI.
2. `AppStore.startListening()` resolves the effective capture path.
3. `AppStore` constructs either `LoopbackCaptureService` or `MicrophoneCaptureService`.
4. The chosen service continues emitting audio level updates and PCM chunks.
5. Existing streaming-client and socket flow remain unchanged.
6. UI reads derived presentation state from `AppStore` and shows the correct live status.

This preserves the current audio-to-socket architecture and limits the change to source resolution and presentation.

## Error Handling

The app should only degrade when the user’s goal remains meaningfully satisfied.

### Degrade gracefully

- Missing loopback for `System Audio` should not hard-fail. It should switch to microphone fallback and update messaging.

### Fail clearly

- Missing loopback for `App Audio` should still block start.
- Missing microphone permission during fallback should show microphone-specific guidance, not loopback guidance.
- Capture-service startup failures should still stop the session cleanly and surface the right failure reason.
- Backend socket failures should continue using the existing shutdown and error-display behavior.

This avoids hidden behavior for cases where fallback would misrepresent what the user asked for.

## Testing

The new tests should concentrate on store decisions and presentation state, not on rewriting low-level audio conversion coverage.

### Add tests for

- `System Audio` with loopback available chooses loopback capture
- `System Audio` without loopback chooses microphone capture
- `App Audio` without loopback refuses start
- derived presentation state matches each scenario
- fallback updates setup or status messaging correctly
- session metadata preserves intended source and records effective path

### Keep existing tests

- loopback PCM conversion coverage
- streaming client behavior
- existing microphone and history behavior not affected by the fallback policy

## Risks And Mitigations

### Risk: misleading terminology

If fallback labels still imply routed system capture, users may assume the app is hearing all system audio when it is only hearing local microphone input.

Mitigation:

- use `Live Audio` wording for fallback
- avoid saying “system-wide streaming audio” when fallback is active

### Risk: conditionals spread across views

If each screen calculates fallback behavior independently, UI copy and status pills will drift.

Mitigation:

- centralize effective capture-path derivation in `AppStore`

### Risk: history loses diagnostic value

If only the intended source is stored, support and debugging may not be able to explain what actually happened in fallback sessions.

Mitigation:

- keep intended source
- record effective capture path in session metadata

## Implementation Notes

- Prefer derived state over mutating `selectedSource` during fallback.
- Preserve the current `AudioCaptureServicing` protocol contract.
- Preserve the current PCM-to-socket path after service selection.
- Keep the first version limited to `System Audio` fallback only.

## Success Criteria

- A user without BlackHole can select `System Audio` and start a live session successfully.
- The session captures through microphone fallback rather than failing at startup.
- The UI makes it clear that fallback is active using `Live Audio`-style messaging.
- `App Audio` still behaves honestly and does not pretend to support fallback.
- The change is covered by focused `AppStore` tests.
