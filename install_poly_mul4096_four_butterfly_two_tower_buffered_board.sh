#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
board="${1:-pynq}"
remote_dir="${2:-/home/xilinx/jupyter_notebooks/p4ttbo}"
deploy_dir="$repo/deploy/poly_mul4096_four_butterfly_two_tower_buffered_dma"

[[ -d "$deploy_dir" ]] || {
    echo "error: deploy directory not found: $deploy_dir" >&2
    echo "build the buffered overlay first" >&2
    exit 1
}

tar -C "$deploy_dir" -cf - . \
    | ssh "xilinx@$board" \
        "mkdir -p '$remote_dir' && tar -C '$remote_dir' -xf -"

echo
echo "Installed on $board:$remote_dir"
echo
echo "Run:"
echo "  ssh xilinx@$board"
echo "  cd $remote_dir"
echo "  ./run_poly_mul4096_four_butterfly_two_tower_buffered_board.sh"
