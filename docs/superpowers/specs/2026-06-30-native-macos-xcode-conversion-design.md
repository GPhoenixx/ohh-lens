# Native macOS Xcode Conversion Design

## Goal

Convert Ohh Lens from a SwiftPM executable into a native Xcode macOS SwiftUI application. The conversion must produce a normal `.app` bundle, preserve existing behavior and tests, and remove SwiftPM from the project.

## Project Structure

Create `OhhLens.xcodeproj` with two targets:

- `OhhLens`: a macOS SwiftUI application target containing the files currently under `Sources/OhhLensApp` and `Sources/OhhLensCore`.
- `OhhLensTests`: a macOS unit-test target containing the files currently under `Tests/OhhLensCoreTests`.

The existing source directories remain in place to keep the diff readable, but both source trees become part of the single `OhhLens` app module. `Package.swift` is removed. Source files no longer import `OhhLensCore`, and tests use `@testable import OhhLens`.

## App Configuration

The app target will:

- Use macOS 14 as its minimum deployment target.
- Use the existing `OhhLensApp` SwiftUI `@main` entry point.
- Produce an application bundle named `Ohh Lens` with bundle identifier `com.ohhlens.app`.
- Generate its Info.plist from build settings, including a microphone usage description.
- Keep automatic code signing enabled with no hard-coded development team.
- Keep App Sandbox disabled during this conversion so existing local backend process launching, local WebSocket access, history-file access, and audio-device discovery continue to work. Sandboxing and distribution entitlements are a separate shipping task.

The existing `WindowGroup`, native `NavigationSplitView`, explicit sidebar selection, and dedicated `Settings` scene remain unchanged.

## Tests

The Xcode test target will compile the existing unit tests against the app module. Test source imports will be updated from `OhhLensCore` to `OhhLens`. The conversion is successful when:

- `xcodebuild build -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS'` succeeds.
- `xcodebuild test -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS'` executes the existing test suite.
- The generated `.app` launches and presents the main SwiftUI window.

Any pre-existing test failure caused by an intentional working-tree behavior change is reported separately from conversion failures.

## Developer Workflow

Update `script/build_and_run.sh` to use `xcodebuild`, locate the Debug `.app` from Xcode's derived data output, terminate an older Ohh Lens process, and open the newly built bundle. Keep `.codex/environments/environment.toml` pointing to that script.

Developers can open `OhhLens.xcodeproj` directly in Xcode, use native SwiftUI previews, run the app with Command-R, and run tests with Command-U.

## Scope Boundaries

This conversion does not redesign the UI, change transcription behavior, package the Python backend, enable App Sandbox, configure a paid Apple development team, notarize the app, or prepare App Store distribution. The backend directory remains unchanged.

