#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${1:-/home/xilinx/jupyter_notebooks/evalmul3_bv_relinearized}"
CIPHERTEXTS="${2:-8}"
TIMED_RUNS="${3:-5}"

source /etc/profile.d/xrt_setup.sh

cd "$REMOTE_DIR"

python3 \
  run_fpga_evalmul3_bv_relinearized.py \
  --overlay "$REMOTE_DIR/evalmul3_bv_relinearized_dma150.bit" \
  --vectors "$REMOTE_DIR/vectors" \
  --results "$REMOTE_DIR/results/c${CIPHERTEXTS}" \
  --timed-runs "$TIMED_RUNS" \
  --ciphertexts "$CIPHERTEXTS"
