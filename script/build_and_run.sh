#!/usr/bin/env bash
# script/build_and_run.sh
set -euo pipefail
swift build
swift run OhhLensApp
