#!/usr/bin/env bash
set -euo pipefail
echo "DEPRECATED: use scripts/vivado/build_bv_keyreuse_multi_pair_session_dma150_overlay.sh" >&2
exec "$(dirname "$0")/scripts/vivado/build_bv_keyreuse_multi_pair_session_dma150_overlay.sh" "$@"
fi
exit "$status"
