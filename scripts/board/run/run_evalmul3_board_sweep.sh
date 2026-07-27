#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${1:-/home/xilinx/jupyter_notebooks/evalmul3}"
TIMED_RUNS="${2:-5}"

source /etc/profile.d/xrt_setup.sh

cd "$REMOTE_DIR"

for ciphertexts in 32 64 128 256; do
  echo
  echo "============================================================"
  echo "EVALMUL3_BATCH_SWEEP ciphertexts=$ciphertexts"
  echo "============================================================"

  python3 \
    run_fpga_evalmul3.py \
    --overlay "$REMOTE_DIR/evalmul3_two_tower_dma.bit" \
    --vectors "$REMOTE_DIR/vectors" \
    --results "$REMOTE_DIR/results_sweep/c${ciphertexts}" \
    --timed-runs "$TIMED_RUNS" \
    --ciphertexts "$ciphertexts"
done
