#!/usr/bin/env bash
# script/build_and_run.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="$ROOT_DIR/OhhLens.xcodeproj"
DERIVED_DATA="$ROOT_DIR/.build/xcode"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/Ohh Lens.app"

export HOME="$ROOT_DIR/.home"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.cache/clang/ModuleCache"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

mkdir -p "$HOME" "$CLANG_MODULE_CACHE_PATH"

pkill -x "Ohh Lens" 2>/dev/null || true

xcodebuild \
  -project "$PROJECT" \
  -scheme OhhLens \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build

open -n "$APP_PATH"
