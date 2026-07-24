#!/usr/bin/env bash
set -euo pipefail

source /etc/profile.d/pynq_venv.sh
source /etc/profile.d/xrt_setup.sh

cd /home/xilinx/board_db2r

python3 test_db2r_openfhe_buffered_sweep_dma.py \
  --overlay poly_mul4096_dual_butterfly_two_tower_buffered_dma.bit \
  --vectors vectors \
  --output fpga_buffered \
  --batch-counts 1 2 4 8 16 \
  --timed-batches 20 \
  --openfhe-reference-us 7161.35
