# Ping-pong BV accumulator pipeline timing fix

The five-strategy timing sweep reduced the miss to:

```text
best strategy:   DefaultExplore
best stage:      post_phys
WNS:             -0.017 ns
failing paths:   5
```

The timing report identifies the actual path:

```text
bv_meta_read_pointer
    -> bv_meta_ciphertext distributed RAM
    -> ks_a/ks_b accumulator distributed RAM
    -> 32-bit modular-add carry chains
    -> accumulator distributed-RAM write input
```

The worst path contains fourteen logic levels:

```text
RAMD32
RAMD64E
LUT2
9 x CARRY4
LUT4
LUT5
RAMD64E write
```

It is the BV accumulator read-modify-write path, not the output bank mux.

## Fix

This patch inserts one register boundary:

```text
cycle n:
    metadata FIFO read
    accumulator RAM read
    register address, bank, digit, old value, and multiplier result

cycle n+1:
    modular add
    accumulator RAM write
```

Final-digit completion is now counted at the stage-1 write, so a coefficient
cannot become output-ready before its final accumulator values have committed.

Throughput remains one BV result per cycle. The existing minimum batch of eight
keeps repeated accesses to the same ciphertext far enough apart to avoid a
read-after-write hazard.

## Apply and rerun exact simulation

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_pingpong_accumulator_pipeline_fix.zip

./scripts/sim/run_bv_keyreuse_pingpong_checkpoint.sh
```

Expected ending:

```text
PINGPONG_OVERLAP_HANDSHAKES=...
PASS: exact ping-pong coefficient-major BV evaluation-key reuse across all six tower pairs
PASS: exact ping-pong coefficient-major evaluation-key-reuse checkpoint complete
```

After exact simulation passes, rerun the existing physical sweep:

```bash
./scripts/vivado/build_bv_keyreuse_pingpong_timing_sweep.sh
```

The long path should be split into two substantially shorter paths:

```text
metadata/accumulator read -> pipeline registers
pipeline registers -> modular add -> accumulator write
```
