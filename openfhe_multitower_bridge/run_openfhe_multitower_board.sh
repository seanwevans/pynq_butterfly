#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

TIMED_RUNS="${1:-3}"
ARTIFACT="poly_mul4096_four_butterfly_two_tower_buffered_dma"

if [[ -f /etc/profile.d/xrt_setup.sh ]]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/xrt_setup.sh
fi

python_candidates=(
  /usr/local/share/pynq-venv/bin/python3
  /home/xilinx/pynq/bin/python3
  /usr/bin/python3
)

python_bin=""
for candidate in "${python_candidates[@]}"; do
  if [[ -x "$candidate" ]] \
    && "$candidate" -c 'import pynq, numpy' >/dev/null 2>&1; then
    python_bin="$candidate"
    break
  fi
done

if [[ -z "$python_bin" ]]; then
  echo "error: could not find a Python interpreter with pynq and numpy" >&2
  exit 1
fi

rm -rf "$ROOT/results"
mkdir -p "$ROOT/results"

"$python_bin" \
  "$ROOT/run_fpga_multitower_buffered.py" \
  --overlay "$ROOT/$ARTIFACT.bit" \
  --vectors "$ROOT/vectors" \
  --results "$ROOT/results" \
  --timed-runs "$TIMED_RUNS"

if id xilinx >/dev/null 2>&1; then
  chown -R xilinx:xilinx "$ROOT/results"
fi
