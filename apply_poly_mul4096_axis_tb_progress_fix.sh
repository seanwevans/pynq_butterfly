#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 \
  "$repo/fix_poly_mul4096_axis_tb_progress.py" \
  "$repo"

exec "$repo/compile_poly_mul4096_four_butterfly_two_tower_axis.sh"
