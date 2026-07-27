#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"$repo/scripts/synth/compile_ntt4096_four_butterfly_shared_ab.sh"
"$repo/scripts/synth/implement_ntt4096_four_butterfly_shared_ab.sh"

python3 \
    "$repo/scripts/sim/check_ntt4096_four_butterfly_shared_ab.py" \
    --repo "$repo" \
    --minimum-wns 0.0
