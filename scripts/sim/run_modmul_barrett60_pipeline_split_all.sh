#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"$repo/scripts/synth/compile_modmul_barrett60_pipeline_split.sh"
"$repo/scripts/synth/implement_modmul_barrett60_pipeline_split.sh"
python3 \
    "$repo/tests/support/check_modmul_barrett60_pipeline_split.py" \
    --repo "$repo" \
    --minimum-wns 0.0
