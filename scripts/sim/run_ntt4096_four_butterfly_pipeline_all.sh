#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"$repo/scripts/synth/compile_ntt4096_four_butterfly_pipeline.sh"
"$repo/scripts/synth/implement_ntt4096_four_butterfly_pipeline.sh"

python3 \
    "$repo/tests/support/check_ntt4096_four_butterfly_pipeline.py" \
    --repo "$repo" \
    --minimum-wns 0.0
