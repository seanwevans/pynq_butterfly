#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${1:-/home/xilinx/jupyter_notebooks/evalmul3_dma150}"
CIPHERTEXTS="${2:-256}"
TIMED_RUNS="${3:-5}"

source /etc/profile.d/xrt_setup.sh

cd "$REMOTE_DIR"

python3 \
  run_fpga_evalmul3.py \
  --overlay "$REMOTE_DIR/evalmul3_two_tower_dma150.bit" \
  --vectors "$REMOTE_DIR/vectors" \
  --results "$REMOTE_DIR/results/c${CIPHERTEXTS}" \
  --timed-runs "$TIMED_RUNS" \
  --ciphertexts "$CIPHERTEXTS"
