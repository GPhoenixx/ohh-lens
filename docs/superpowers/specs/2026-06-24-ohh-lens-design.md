# Ohh Lens Design Spec

Date: 2026-06-24
Status: Approved for spec drafting
Product: Ohh Lens
Platform: macOS

## Summary

Ohh Lens is a native macOS subtitle app that captures spoken audio from multiple local sources, sends short audio chunks to a locally managed FunASR-based backend, and renders live subtitles in both a main app window and an always-on-top overlay. The product targets both media viewers and multilingual meetings or classes. It supports transcript and translation output, saves local session history, and guides users through setup for permissions, local backend health, and virtual audio device installation.

## Product Goals

- Let users understand spoken content on their Mac in real time.
- Support microphone, system audio, app-audio-via-virtual-device, and file transcription in one app.
- Provide flexible subtitle display modes for original text, translated text, or both.
- Feel like a consumer-ready desktop product rather than a developer utility.
- Keep user data local by default.

## Non-Goals For V1

- Cloud processing or remote speech services.
- Account sync or cross-device transcript sync.
- Real-time collaborative sharing.
- Deep transcript editing tools.
- Advanced media management beyond import, history, and export.

## Primary Users

- People watching videos, streams, or spoken content and wanting live subtitles.
- People in multilingual meetings, classes, or presentations who want live transcription and translation.

## Product Positioning

Ohh Lens should feel like a polished desktop utility with a stronger live-broadcast personality in the overlay. The app shell should remain calmer and more utility-focused for long sessions, while the live caption experience should feel immediate, visible, and distinctive.

## High-Level Architecture

The system is split into five clear parts:

1. Capture Layer
   Handles microphone capture, system-audio capture through a virtual audio device, selected-app audio through that same routing model when available, and file import.

2. Session Pipeline
   Converts all capture sources into timestamped short audio chunks with metadata such as source type, session ID, and language settings.

3. Local Service Manager
   Starts, stops, monitors, and reconnects to a locally managed FunASR-based backend service. Sends audio chunks for transcription and translation and receives text results.

4. Presentation Layer
   Powers the main desktop window and the always-on-top subtitle overlay.

5. Local Storage Layer
   Saves preferences, sessions, transcript segments, translated segments, exports, and service/setup state locally on-device.

## Responsibility Boundaries

- The macOS app owns capture, permissions, setup flow, service lifecycle UX, storage, overlay behavior, and session history.
- The FunASR backend owns speech-to-text and translation processing.
- The app and backend communicate through a local service interface on the user’s machine.

This separation keeps the macOS app responsive and allows the backend internals to evolve without forcing a redesign of the desktop product.

## Main App Structure

The main app window has four primary areas:

- Live
  The operational hub for source selection, language settings, start or stop listening, and opening the live overlay.

- History
  Displays saved sessions with search, reopen, copy, and export actions.

- Files
  Supports offline or batch transcription from imported audio or video files.

- Setup
  Walks users through permissions, virtual audio device installation or detection, and local backend health.

## Overlay Window

The subtitle overlay is a separate always-on-top window designed for live use over video, meetings, or other apps. It should include:

- Pause or resume
- Pin or unpin
- Source label
- Language pair
- Quick mode switching between:
  - original only
  - translation only
  - dual-line original plus translation

The overlay uses the chosen visual direction: broadcast-leaning, high-contrast, and immediate, while keeping subtitle typography readable and accessible.

## User Flow

The intended core flow is:

1. Open the app.
2. Complete setup once for permissions, virtual audio device, and backend readiness.
3. Choose a source and language pair in Live.
4. Start listening.
5. View captions in the floating overlay immediately.
6. Review, search, reopen, or export the saved session later from History.

## Audio Sources And Modes

V1 supports these source paths:

- Microphone
- System audio through a virtual audio device workflow
- App audio via the same virtual audio device routing model
- Imported audio or video files

The system should degrade gracefully. If the virtual audio device is unavailable, microphone and file modes should still work.

## Backend And Service Management

The local FunASR service is treated as part of the product experience, not an external manual prerequisite.

On app launch, the app should:

- Detect whether the backend is installed and available
- Start it if needed
- Wait for a health signal
- Show a clear status such as Starting, Ready, or Needs Attention

The Setup area should also allow:

- Start service
- Stop service
- Restart service
- View health state
- View actionable error guidance

Failure messages should be plain-language and specific, for example:

- Missing model files
- Port already in use
- Python or runtime issue
- Service failed health check

The user should always get a next action rather than a generic failure message.

## Translation Behavior

V1 includes translation support in addition to raw transcription.

The overlay and main experience should support quick switching between:

- Original speech only
- Translated text only
- Original plus translated text

This needs to work well for both passive viewing and language-learning or meeting scenarios.

## Storage And Retention

Every session is saved locally with:

- Source type
- Language pair
- Timestamps
- Transcript segments
- Translated segments
- Optional linked file reference for file-based sessions

History should support:

- Search
- Reopen
- Copy
- Export

Initial export formats:

- `.txt`
- `.srt`

Raw captured audio retention is optional and off by default. By default, the app keeps transcript and translation history but does not keep raw captured audio after the session unless the user explicitly enables retention.

## Privacy Defaults

- Processing is local-first through a local backend service on the user’s machine.
- Session history is stored locally.
- Raw captured audio is not retained by default.
- Users can explicitly opt into raw-audio retention if they want it.

## Error Handling And Recovery

The app must degrade cleanly:

- If the backend disconnects mid-session:
  - show a clear paused or error state in the overlay
  - retry briefly
  - then ask the user to intervene if recovery fails

- If audio permissions are missing:
  - route the user back into Setup with clear next steps

- If the virtual audio device is unavailable:
  - preserve microphone and file modes
  - explain why system or app audio is unavailable

- If translation is temporarily unavailable:
  - preserve transcription when possible
  - clearly communicate reduced functionality

## UI And UX Direction

The visual direction is based on the chosen "Live Broadcast Energy" concept for the overlay, with a calmer utility shell in the main window.

Visual principles:

- High-contrast live overlay
- Clear, accessible subtitle typography
- Fast-status readability
- Strong source and state visibility
- Minimal friction for switching modes
- Utility-first layout in the main app to support long sessions

Accessibility principles:

- Maintain readable contrast
- Keep controls large enough for desktop interaction
- Preserve visible focus states
- Respect reduced-motion settings
- Use accessible labels for all interactive controls
- Avoid color-only meaning

## V1 Testing Strategy

Testing must cover four levels:

1. Capture tests
   Validate microphone, virtual-device system audio, app audio routing path, and file import.

2. Service tests
   Validate start, stop, restart, reconnect, and unhealthy-backend behavior.

3. Subtitle behavior tests
   Validate chunk timing, overlay refresh, live updates, and subtitle mode switching.

4. Storage tests
   Validate session save, search, reopen, copy, and export.

Unhappy-path coverage must include:

- Missing permissions
- Virtual audio device not installed
- Backend startup failure
- Translation unavailable
- Backend disconnect during a live session

## V1 Scope Checklist

Included:

- Native macOS app
- Main app window
- Floating always-on-top overlay
- Local FunASR service management
- Guided setup
- Microphone input
- System audio input through virtual audio device flow
- App audio through the same routing path
- File import for audio and video
- Transcript plus translation display modes
- Local history
- Search and export

Excluded:

- Cloud processing
- Account system
- Sync
- Collaboration
- Advanced transcript editing

## Implementation Notes For Planning

The next planning phase should assume:

- A native macOS app implementation
- A build flow aligned with the `build-macos-apps` plugin guidance
- A clean separation between app UX and local backend processing
- A setup flow robust enough for non-technical users
- A shippable first release rather than a demo-only prototype

## Open Assumptions

These assumptions are fixed for the plan unless the user changes them:

- Backend processing is provided by a locally managed FunASR-based service.
- The app will support both live and file-based workflows.
- Overlay subtitle mode is user-switchable.
- Raw audio retention is optional and off by default.
- The first release prioritizes a polished end-user setup experience rather than a developer-only workflow.
