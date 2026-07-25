# Arbitrary-tower OpenFHE bridge

This checkpoint generalizes the timing-closed two-tower PYNQ-Z2 multiplier to
an arbitrary OpenFHE `DCRTPoly` tower count without changing the FPGA RTL.

The bridge:

1. creates exact coefficient-format OpenFHE `DCRTPoly` inputs;
2. derives a descending RNS prime chain and roots of unity;
3. generates one runtime NTT profile per tower;
4. groups towers into pairs for the existing 64-bit DMA interface;
5. runs every pair as a buffered `MULB` batch;
6. handles an odd final tower by duplicating it into both hardware lanes and
   discarding the duplicate result;
7. imports every FPGA tower back into complete `DCRTPoly` objects;
8. requires exact object equality with OpenFHE.

The current hardware remains fixed at:

```text
N                         4096
clock                     100 MHz
arithmetic                 22968 clocks/product
four-wide handoff           1025 clocks/product
steady cadence             23993 clocks/tower-pair product
measured batch-128 rate     4038.65 tower-pair products/s
```

## Files

```text
openfhe_multitower_bridge.cpp      OpenFHE vector generator and verifier
run_fpga_multitower_buffered.py    arbitrary-tower PYNQ executor
build.sh                           CMake/OpenFHE build
install_openfhe_multitower_board.sh
run_openfhe_multitower_board.sh
run_openfhe_multitower_e2e.sh      complete host -> board -> host test
```

## Apply

Unzip this directory at the repository root. It expects the preserved overlay
here:

```text
deploy/poly_mul4096_four_butterfly_two_tower_buffered_dma/
  poly_mul4096_four_butterfly_two_tower_buffered_dma.bit
  poly_mul4096_four_butterfly_two_tower_buffered_dma.hwh
```

## Build

```bash
cd /mnt/f/repos/pynq_butterfly/openfhe_multitower_bridge

OPENFHE_PREFIX="$HOME/.local/openfhe-1.5.1" \
  ./build.sh
```

## First end-to-end test

Use 6 towers and 4 products first:

```bash
./run_openfhe_multitower_e2e.sh 6 4 2
```

This will prompt for the normal SSH and PYNQ sudo passwords. Expected ending:

```text
PASS: every FPGA tower equals OpenFHE
PASS: every imported FPGA DCRTPoly equals the OpenFHE object
PASS: arbitrary-tower OpenFHE/PYNQ bridge completed end to end
```

Then run a representative 12-tower batch:

```bash
./run_openfhe_multitower_e2e.sh 12 32 3
```

Arguments are:

```text
TOWER_COUNT PRODUCT_COUNT TIMED_RUNS [SEED]
```

Environment overrides:

```bash
PYNQ_SSH=xilinx@pynq
PYNQ_REMOTE_DIR=/home/xilinx/jupyter_notebooks/p4ttbo_multitower
OPENFHE_PREFIX=$HOME/.local/openfhe-1.5.1
```

## Manual stages

Generate vectors:

```bash
./build/openfhe_multitower_bridge \
  generate vectors/t12_p32 12 32 0x4096f1e2026
```

Install and execute:

```bash
./install_openfhe_multitower_board.sh vectors/t12_p32

ssh xilinx@pynq
sudo bash -lc '
  cd /home/xilinx/jupyter_notebooks/p4ttbo_multitower
  ./run_openfhe_multitower_board.sh 3
'
```

Copy and verify:

```bash
mkdir -p results/t12_p32
scp -r \
  xilinx@pynq:/home/xilinx/jupyter_notebooks/p4ttbo_multitower/results/. \
  results/t12_p32/

./build/openfhe_multitower_bridge \
  verify vectors/t12_p32 results/t12_p32
```

## Throughput interpretation

For `T` towers, one complete `DCRTPoly` product requires `ceil(T/2)` FPGA
pair-products. With 12 towers, the raw batch-128 measurement predicts roughly:

```text
4038.65 / 6 = 673.1 complete DCRTPoly products/s
```

The board runner reports both:

```text
effective_tower_pair_products_per_second
compute_DCRTPoly_products_per_second
end_to_end_DCRTPoly_products_per_second
```

The difference between compute and end-to-end includes profile loading. The
host-side `ProfileFrameCache` caches packed profile frames by modulus, root, and
cyclotomic order; the FPGA still stores one active profile pair, so each unique
pair must be loaded once per grouped batch.

## Next integration boundary

This proves the exact arbitrary-tower data path. The following step is to turn
the file-backed executor into a long-lived service or direct C++ backend so
OpenFHE ciphertext multiplication can submit `DCRTPoly` batches without
serializing vectors to disk. After that, profile banks and key-switch
accumulation become the next hardware targets.
