#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$repo/compile_poly_mul4096_four_butterfly_pipeline.sh"
"$repo/implement_poly_mul4096_four_butterfly_pipeline.sh"

python3 \
    "$repo/check_poly_mul4096_four_butterfly_pipeline.py" \
    --repo "$repo" \
    --minimum-wns 0.0
