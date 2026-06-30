# Native macOS Xcode Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the SwiftPM executable with a native Xcode macOS SwiftUI app and Xcode unit-test target.

**Architecture:** `OhhLens.xcodeproj` owns the existing app and core source directories as one `OhhLens` module. A dependent `OhhLensTests` target compiles the existing tests, while the Python backend remains outside the Xcode project.

**Tech Stack:** Swift 6, SwiftUI, Observation, AVFoundation, XCTest, Xcode build system, macOS 14+

---

### Task 1: Create the native Xcode project

**Files:**
- Create: `OhhLens.xcodeproj/project.pbxproj`
- Create: `OhhLens.xcodeproj/xcshareddata/xcschemes/OhhLens.xcscheme`

- [ ] **Step 1: Establish the failing native-build check**

Run:

```bash
xcodebuild -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS' build
```

Expected: FAIL because `OhhLens.xcodeproj` does not exist.

- [ ] **Step 2: Create the project metadata**

Create a project with filesystem-synchronized source groups for:

```text
Sources/OhhLensApp  -> OhhLens target
Sources/OhhLensCore -> OhhLens target
Tests/OhhLensCoreTests -> OhhLensTests target
```

Configure the app target with:

```text
PRODUCT_NAME = "Ohh Lens"
PRODUCT_BUNDLE_IDENTIFIER = com.ohhlens.app
PRODUCT_MODULE_NAME = OhhLens
MACOSX_DEPLOYMENT_TARGET = 14.0
SWIFT_VERSION = 6.0
GENERATE_INFOPLIST_FILE = YES
INFOPLIST_KEY_NSMicrophoneUsageDescription = "Ohh Lens needs microphone access to transcribe live audio."
CODE_SIGN_STYLE = Automatic
ENABLE_APP_SANDBOX = NO
```

Configure `OhhLensTests` as a unit-test bundle with `TEST_HOST` and `BUNDLE_LOADER` pointing to `Ohh Lens.app/Contents/MacOS/Ohh Lens`, and add an explicit target dependency on `OhhLens`.

- [ ] **Step 3: Create the shared scheme**

The `OhhLens` scheme must build the app for Run/Profile/Archive and build both the app and tests for Test. Set the Run configuration to Debug and Test configuration to Debug.

- [ ] **Step 4: List the project to validate metadata**

Run:

```bash
xcodebuild -list -project OhhLens.xcodeproj
```

Expected: project lists `OhhLens` and `OhhLensTests` targets and the shared `OhhLens` scheme.

### Task 2: Merge source ownership into the app module

**Files:**
- Modify: `Sources/OhhLensApp/ContentView.swift`
- Modify: `Sources/OhhLensApp/OhhLensApp.swift`
- Modify: `Sources/OhhLensApp/Views/HistoryView.swift`
- Modify: `Sources/OhhLensApp/Views/LiveView.swift`
- Modify: `Sources/OhhLensApp/Views/SetupView.swift`
- Modify: every test file under `Tests/OhhLensCoreTests`

- [ ] **Step 1: Run the app build to expose module-import failures**

Run:

```bash
xcodebuild -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS' -derivedDataPath .build/xcode build
```

Expected: FAIL because app files import the former `OhhLensCore` module.

- [ ] **Step 2: Remove obsolete app imports**

Remove this line wherever it appears under `Sources/OhhLensApp`:

```swift
import OhhLensCore
```

Keep `import SwiftUI` and other framework imports unchanged.

- [ ] **Step 3: Point tests at the app module**

Replace:

```swift
@testable import OhhLensCore
```

with:

```swift
@testable import OhhLens
```

in every test source.

- [ ] **Step 4: Build the app module**

Run:

```bash
xcodebuild -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS' -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **` and `.build/xcode/Build/Products/Debug/Ohh Lens.app` exists.

### Task 3: Replace the SwiftPM workflow

**Files:**
- Delete: `Package.swift`
- Modify: `script/build_and_run.sh`
- Keep: `.codex/environments/environment.toml`

- [ ] **Step 1: Replace SwiftPM commands in the run script**

The script must use:

```bash
PROJECT="$ROOT_DIR/OhhLens.xcodeproj"
DERIVED_DATA="$ROOT_DIR/.build/xcode"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/Ohh Lens.app"

pkill -x "Ohh Lens" 2>/dev/null || true
xcodebuild \
  -project "$PROJECT" \
  -scheme OhhLens \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build
open -n "$APP_PATH"
```

Preserve `set -euo pipefail` and the existing root-directory resolution.

- [ ] **Step 2: Remove the SwiftPM manifest**

Delete `Package.swift`; the Xcode project is now the sole Swift build definition.

- [ ] **Step 3: Confirm no active workflow references SwiftPM**

Run:

```bash
rg -n 'swift (build|run|test)|Package.swift|OhhLensCore' script .codex Sources Tests --glob '!*.md'
```

Expected: no obsolete SwiftPM command or module-import matches.

### Task 4: Verify tests and app bundle

**Files:**
- Modify only if required by a conversion-specific compiler or linker error.

- [ ] **Step 1: Run the complete Xcode test suite**

Run:

```bash
xcodebuild -project OhhLens.xcodeproj -scheme OhhLens -destination 'platform=macOS' -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO test
```

Expected: all existing tests execute. Report any pre-existing assertion mismatch separately from build, discovery, host, or linker failures.

- [ ] **Step 2: Inspect the produced bundle**

Run:

```bash
test -x '.build/xcode/Build/Products/Debug/Ohh Lens.app/Contents/MacOS/Ohh Lens'
plutil -p '.build/xcode/Build/Products/Debug/Ohh Lens.app/Contents/Info.plist'
```

Expected: executable exists; Info.plist contains `CFBundleIdentifier = com.ohhlens.app` and `NSMicrophoneUsageDescription`.

- [ ] **Step 3: Validate the developer entry point**

Run:

```bash
bash -n script/build_and_run.sh
```

Expected: script syntax is valid. Launch only after tests pass or known pre-existing failures are documented.

- [ ] **Step 4: Review the final diff**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; backend files and pre-existing SetupView changes remain unmodified by the conversion.

