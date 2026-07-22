#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

OPENFHE_PREFIX="${OPENFHE_PREFIX:-$HOME/.local/openfhe-1.5.1}"

cmake \
  -S "$ROOT" \
  -B "$ROOT/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$OPENFHE_PREFIX"

cmake \
  --build "$ROOT/build" \
  --clean-first \
  --parallel "$(nproc)"

echo
echo "Built:"
echo "  $ROOT/build/openfhe_eval_domain_bridge"
