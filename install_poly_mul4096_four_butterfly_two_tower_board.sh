#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
board="${1:-pynq}"
remote_dir="${2:-/home/xilinx/jupyter_notebooks/p4tt}"
deploy_dir="$repo/deploy/poly_mul4096_four_butterfly_two_tower_dma"
[[ -d "$deploy_dir" ]] || { echo "error: deploy directory not found: $deploy_dir" >&2; exit 1; }
ssh "xilinx@$board" "mkdir -p '$remote_dir'"
scp -r "$deploy_dir/." "xilinx@$board:$remote_dir/"
echo "Installed on $board:$remote_dir"
echo "Run: ssh xilinx@$board 'cd $remote_dir && chmod +x run_poly_mul4096_four_butterfly_two_tower_board.sh && ./run_poly_mul4096_four_butterfly_two_tower_board.sh'"
