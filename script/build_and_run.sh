#!/usr/bin/env bash
# script/build_and_run.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export HOME="$ROOT_DIR/.home"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.cache/clang/ModuleCache"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

mkdir -p "$HOME" "$CLANG_MODULE_CACHE_PATH"

swift build
swift run OhhLensApp
