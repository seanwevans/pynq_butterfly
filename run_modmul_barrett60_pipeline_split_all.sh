#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$repo/compile_modmul_barrett60_pipeline_split.sh"
"$repo/implement_modmul_barrett60_pipeline_split.sh"
python3 \
    "$repo/check_modmul_barrett60_pipeline_split.py" \
    --repo "$repo" \
    --minimum-wns 0.0
