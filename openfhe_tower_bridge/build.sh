#!/usr/bin/env bash
# Compatibility wrapper for the former bridge-local CMake project.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec "$ROOT/scripts/host/build_openfhe_tools.sh" "$@"
