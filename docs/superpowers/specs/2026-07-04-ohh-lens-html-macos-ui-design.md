# Ohh Lens HTML-Matched macOS UI Design

## Goal

Redesign the native macOS Ohh Lens app so its UI matches the reference HTML file at `/Users/steve/Library/Application Support/Open Design/namespaces/release-stable/data/projects/3bdfd7bd-2dcb-44c0-936b-2c3e9ff0aed1/macos-app-only-2.html` as closely as SwiftUI and the current native window model allow. The HTML file is the visual and structural source of truth for this effort.

The redesign should replace the current basic `NavigationSplitView` shell and section layouts with a custom glass-window interface, HTML-matching sidebar navigation, matching tab structure, matching card and control styling, and a native floating PiP overlay that mirrors the HTML component.

## Source of Truth

The implementation will follow the reference HTML directly for:

- overall window composition
- sidebar grouping, labels, and ordering
- section titles and primary controls
- light theme color treatment
- glass-card styling and spacing
- history/archive viewer structure
- file transcription workflow structure
- settings grouping and appearance
- floating PiP overlay appearance and controls

The intended text contrast is:

- default text is black or near-black
- muted text is gray only for metadata and helper copy
- active navigation items use a red background with white text

## App Shell

Replace the current four-section `NavigationSplitView` shell with a custom single-window layout that matches the HTML:

- titlebar spacer with native traffic-light window controls left intact
- glass-like window background and sidebar treatment
- left sidebar with two groups: `Captions` and `Archive`
- bottom sidebar profile block matching the HTML layout
- main content region that swaps custom tab content panes instead of relying on native split-view navigation

The sidebar tab structure becomes:

1. `Live Subtitles`
2. `Conversations`
3. `File Transcriber`
4. `Saved Transcripts`
5. `App Settings`

This structure intentionally replaces the current `Live`, `History`, `Files`, and `Setup` information architecture so the app matches the HTML file instead of merely borrowing its style.

## Screen Mapping

### Live Subtitles

This tab becomes the primary real-time caption stream. It maps to the current live listening feature set, but adopts the HTML structure:

- section header with title, loopback selector, and PiP toggle button
- large caption stream card
- idle state matching the HTML tone and layout
- footer control bar with language selector, translation selector, and primary start-listening button

### Conversations

This tab is a second live-stream presentation that uses the same capture and transcript pipeline as `Live Subtitles`, but renders results as diarized conversation bubbles with speaker labels and timestamps. It should visually match the HTML `Conversations` tab and remain separate from the simpler subtitle-stream view.

### File Transcriber

This tab replaces the current `Files` screen and follows the HTML three-phase workflow:

1. idle drag-and-drop zone
2. processing card with progress bar and step indicators
3. result card with transcript viewer, translation selector, copy action, and export action

The layout and state progression should mirror the HTML closely, while wiring into the native app’s existing or expanded file-transcription state.

### Saved Transcripts

This tab replaces the current `History` page with the HTML’s two-pane archive layout:

- searchable transcript list in the left pane
- selected transcript viewer in the right pane
- transcript metadata header
- translation selector and export controls

### App Settings

This tab visually replaces `Setup` with the HTML settings layout while preserving important native app health/setup functionality. It should combine:

- loopback device selection
- backend and diagnostics state
- permissions guidance
- transcription/display settings
- appearance controls inspired by the HTML settings groups

Where the HTML mentions controls that do not yet exist in the native app, the visual slots may be introduced first and then backed by real state where appropriate.

## Behavior and Data Flow

The redesign should preserve the current service layer and reuse `AppStore`-driven state wherever possible. UI changes should primarily reorganize and restyle state presentation rather than rewrite the underlying capture pipeline.

### Shell State

Introduce a single selected-tab state for the custom shell. This replaces the current `NavigationSplitView` selection model and drives which HTML-matching pane is visible inside the window body.

### Live Subtitles and Conversations

Both live tabs read from the same live transcript pipeline and listening controls in `AppStore`, but render different views of the same session state:

- `Live Subtitles` shows a subtitle stream optimized for direct reading
- `Conversations` shows diarized speaker-grouped entries

If existing store state is insufficient for the conversation view, add focused presentation state without changing the capture-service contract unnecessarily.

### File Transcriber

Add or extend UI state for:

- selected/imported file
- idle vs processing vs completed phase
- progress percentage
- step status
- completed transcript content
- translation/export UI state

This state should be explicit enough to drive the HTML-style staged screen without scattering workflow logic across views.

### Saved Transcripts

Use the existing history data as the backing store, while adding local or shared UI state for:

- selected transcript
- search query
- viewer translation mode
- export action availability

### App Settings

Centralize settings-facing state so the HTML-style settings page can read:

- backend service health
- setup diagnostics
- available loopback devices
- selected loopback device
- appearance/theme choices
- any additional caption-display preferences needed for the PiP and live views

### Floating PiP

The PiP overlay becomes a native window or overlay surface controlled from shared app state. It should be openable from both live tabs and display the latest visible caption output with styling closely matching the HTML PiP component.

## Design System

Build a shared SwiftUI design layer before converting screens individually. The shared layer should include:

- custom sidebar row styling
- section headers
- glass cards and pane containers
- button variants
- select/control wrappers
- transcript row/bubble styles
- search field styling
- settings row/group styling
- status badges and helper labels

This keeps the implementation maintainable while still targeting a close HTML match.

## Native Constraints

The implementation should stay as faithful to the HTML as possible, with these explicit constraints:

- the actual macOS traffic-light titlebar controls remain system-owned unless a later task intentionally customizes window chrome
- the PiP surface is implemented with native macOS windowing/overlay code rather than web code
- if a web-specific flourish cannot be reproduced exactly in SwiftUI without harming usability or stability, prefer the closest visual/native equivalent and document the exception

## Implementation Order

Implement in this order:

1. shared SwiftUI design system and custom shell
2. `Live Subtitles`
3. `Conversations`
4. `File Transcriber`
5. `Saved Transcripts`
6. `App Settings`
7. native PiP polish and cross-tab integration

This order front-loads the reusable structure and the most visually defining screens.

## Testing and Verification

Verification should include:

- successful macOS app build
- tab switching across all five HTML-matched sections
- live listening controls still starting and stopping correctly
- live transcript rendering still updating in the restyled views
- history/search/viewer interactions still functioning
- file-transcription staged UI behavior behaving correctly for idle, processing, and completed states
- settings/setup data still visible after the shell rewrite
- PiP open/close and content updates functioning from live views

Any mismatch between the HTML reference and native behavior that remains after implementation should be called out clearly.

## Scope Boundaries

This redesign does not intentionally change:

- backend transcription service behavior
- core capture pipeline semantics
- non-UI Python backend architecture
- unrelated packaging or signing work

Small store or model additions are in scope only when they are required to support the HTML-matched UI structure and controls.
