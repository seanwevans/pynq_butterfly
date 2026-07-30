#!/usr/bin/env bash
set -euo pipefail
echo "DEPRECATED: use scripts/board/install/install_bv_keyreuse_multi_pair_session_board.sh" >&2
exec "$(dirname "$0")/scripts/board/install/install_bv_keyreuse_multi_pair_session_board.sh" "$@"
