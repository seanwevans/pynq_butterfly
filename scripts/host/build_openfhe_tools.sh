#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SOURCE="$ROOT/host/openfhe"
BUILD_DIR="${OPENFHE_BUILD_DIR:-$SOURCE/build}"
PREFIX="${OPENFHE_PREFIX:-$HOME/.local/openfhe-1.5.1}"
cmake -S "$SOURCE" -B "$BUILD_DIR" -DCMAKE_PREFIX_PATH="$PREFIX" "$@"
cmake --build "$BUILD_DIR" --parallel
printf 'OpenFHE tools built in %s/tools\n' "$BUILD_DIR"
