#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 \
    "$here/test_poly_mul4096_four_butterfly_two_tower_dma.py" \
    --overlay "$here/poly_mul4096_four_butterfly_two_tower_dma.bit" \
    --vectors "$here/vectors" \
    --timed-runs "${1:-20}"
