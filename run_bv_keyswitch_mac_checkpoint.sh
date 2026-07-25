#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

"$ROOT/scripts/sim/run_bv_keyswitch_mac_openfhe_sim.sh" \
  "${1:-$ROOT/openfhe_eval_domain_bridge/vectors/relin_bv_t12_d0}"
