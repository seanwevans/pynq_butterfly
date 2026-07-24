#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

cd "$ROOT"

./scripts/sim/run_evalmul3_all_tower_axis_sim.sh

echo
echo "PASS: all-pair RTL checkpoint complete"
