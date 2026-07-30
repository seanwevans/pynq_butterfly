#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
usage() { echo "usage: $0 {fast|rtl|host|board} [arguments ...]" >&2; exit 2; }

group="${1:-}"
[[ -n "$group" ]] || usage
shift

case "$group" in
    fast) exec "$repo/scripts/run_sim_regression.sh" --quick "$@" ;;
    rtl) exec "$repo/scripts/run_sim_regression.sh" --all "$@" ;;
    host)
        if ! find "$repo/tests/host" -type f -name 'test_*.py' -print -quit | grep -q .; then
            echo "SKIP host (no host tests are currently defined)"
            exit 0
        fi
        exec python3 -m pytest "$repo/tests/host" "$@"
        ;;
    board)
        [[ "${PYNQ_BOARD_TESTS:-0}" == 1 ]] || {
            echo "SKIP board (set PYNQ_BOARD_TESTS=1 on a configured PYNQ board)"
            exit 0
        }
        exec python3 -m pytest "$repo/tests/board" "$@"
        ;;
    *) usage ;;
esac
