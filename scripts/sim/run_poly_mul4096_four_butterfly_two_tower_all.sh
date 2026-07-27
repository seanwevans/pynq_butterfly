#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"$repo/scripts/synth/compile_poly_mul4096_four_butterfly_two_tower.sh"
"$repo/scripts/synth/implement_poly_mul4096_four_butterfly_two_tower.sh"

python3 \
    "$repo/scripts/sim/check_poly_mul4096_four_butterfly_two_tower.py" \
    --repo "$repo" \
    --minimum-wns 0.0
