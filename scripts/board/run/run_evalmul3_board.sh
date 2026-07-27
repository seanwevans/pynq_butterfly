#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${1:-/home/xilinx/jupyter_notebooks/evalmul3}"
TIMED_RUNS="${2:-3}"

source /etc/profile.d/xrt_setup.sh

cd "$REMOTE_DIR"

sudo -E \
  "$(command -v python3)" \
  run_fpga_evalmul3.py \
  --overlay "$REMOTE_DIR/evalmul3_two_tower_dma.bit" \
  --vectors "$REMOTE_DIR/vectors" \
  --results "$REMOTE_DIR/results" \
  --timed-runs "$TIMED_RUNS"
