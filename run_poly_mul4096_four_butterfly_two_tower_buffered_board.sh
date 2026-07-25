#!/usr/bin/env bash
set -eo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for setup in \
    /etc/profile.d/pynq_venv.sh \
    /etc/profile.d/pynq_setup.sh \
    /etc/profile.d/xrt_setup.sh
do
    if [[ -f "$setup" ]]; then
        # shellcheck disable=SC1090
        source "$setup"
    fi
done

python_bin="${PYNQ_PYTHON:-/usr/local/share/pynq-venv/bin/python3}"

exec "$python_bin" \
    "$here/test_poly_mul4096_four_butterfly_two_tower_buffered_dma.py" \
    --overlay \
    "$here/poly_mul4096_four_butterfly_two_tower_buffered_dma.bit" \
    --vectors \
    "$here/vectors" \
    --batch-sizes \
    "${1:-1,2,4,8,16,32}" \
    --timed-runs \
    "${2:-5}"
