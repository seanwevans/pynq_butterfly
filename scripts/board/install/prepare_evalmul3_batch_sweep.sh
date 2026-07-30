#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."
  pwd
)"

TOWERS="${1:-12}"
MAX_CIPHERTEXTS="${2:-256}"
SEED="${3:-0xe1a140962026}"

BRIDGE="$ROOT/openfhe_eval_domain_bridge/build/openfhe_eval_domain_bridge"
VECTOR_DIR="$ROOT/openfhe_eval_domain_bridge/vectors/t${TOWERS}_c${MAX_CIPHERTEXTS}"

[[ -x "$BRIDGE" ]] || {
  echo "error: missing bridge executable: $BRIDGE" >&2
  echo "run openfhe_eval_domain_bridge/build.sh first" >&2
  exit 1
}

"$BRIDGE" \
  generate \
  "$VECTOR_DIR" \
  "$TOWERS" \
  "$MAX_CIPHERTEXTS" \
  "$SEED"

echo
echo "Vector set:"
echo "  $VECTOR_DIR"
echo
echo "Install with:"
echo "  ./install_evalmul3_sweep_board.sh '$VECTOR_DIR'"
