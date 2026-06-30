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

for _ in 1 2 3 4 5; do
  if ! pgrep -x "Ohh Lens" >/dev/null; then
    break
  fi
  sleep 1
done

if pgrep -x "Ohh Lens" >/dev/null; then
  echo 'Error: "Ohh Lens" did not stop within 5 seconds.' >&2
  exit 1
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme OhhLens \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build

open -n "$APP_PATH"
