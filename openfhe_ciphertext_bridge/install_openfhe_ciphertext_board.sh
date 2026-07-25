#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

REPO_ROOT="$(cd -- "$ROOT/.." && pwd)"

PYNQ_SSH="${PYNQ_SSH:-xilinx@pynq}"
REMOTE_DIR="${PYNQ_REMOTE_DIR:-/home/xilinx/jupyter_notebooks/p4ttbo_ciphertext}"
VECTOR_DIR="${1:?usage: $0 VECTOR_DIRECTORY}"

ARTIFACT="poly_mul4096_four_butterfly_two_tower_buffered_dma"
DEPLOY_DIR="$REPO_ROOT/deploy/$ARTIFACT"

required=(
  "$DEPLOY_DIR/$ARTIFACT.bit"
  "$DEPLOY_DIR/$ARTIFACT.hwh"
  "$ROOT/run_fpga_ciphertext_buffered.py"
  "$ROOT/run_openfhe_ciphertext_board.sh"
  "$VECTOR_DIR/metadata.json"
)

for path in "${required[@]}"; do
  [[ -e "$path" ]] || {
    echo "error: missing required path: $path" >&2
    exit 1
  }
done

ssh "$PYNQ_SSH" \
  "rm -rf '$REMOTE_DIR' && mkdir -p '$REMOTE_DIR'"

scp \
  "$DEPLOY_DIR/$ARTIFACT.bit" \
  "$DEPLOY_DIR/$ARTIFACT.hwh" \
  "$ROOT/run_fpga_ciphertext_buffered.py" \
  "$ROOT/run_openfhe_ciphertext_board.sh" \
  "$PYNQ_SSH:$REMOTE_DIR/"

scp -r \
  "$VECTOR_DIR" \
  "$PYNQ_SSH:$REMOTE_DIR/vectors"

ssh "$PYNQ_SSH" \
  "chmod +x \
    '$REMOTE_DIR/run_openfhe_ciphertext_board.sh' \
    '$REMOTE_DIR/run_fpga_ciphertext_buffered.py'"

echo
echo "Installed:"
echo "  $PYNQ_SSH:$REMOTE_DIR"
