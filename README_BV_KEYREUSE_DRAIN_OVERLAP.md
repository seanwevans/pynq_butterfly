# Coefficient-major compute-drain overlap checkpoint

The board sweep matches the current ping-pong scheduler model almost exactly:

```text
batch  predicted data rate  measured data rate
8      176.91/s             177.11/s
16     208.67/s             208.65/s
32     229.24/s             229.23/s
64     241.13/s             241.19/s
```

The current design overlaps AXI output, but waits for multiplier and BV
accumulator drain before starting the next coefficient.

This checkpoint removes that boundary.

## Change

At the final accepted input word of coefficient `k`:

```text
bank k remains occupied and drains bank-tagged results
the alternate free bank immediately begins coefficient k+1
```

Eval and BV metadata carry a bank bit. Completion counts are independent for
the two banks. A bank becomes output-ready only when both its Eval results and
its final-digit BV accumulator commits reach the batch count.

## Apply and simulate

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_drain_overlap_exact_sim_checkpoint.zip

./run_bv_keyreuse_drain_overlap_checkpoint.sh
```

Expected ending:

```text
PINGPONG_OUTPUT_OVERLAP_HANDSHAKES=...
PINGPONG_DRAIN_OVERLAP_HANDSHAKES=...
PASS: exact coefficient input overlapped prior-bank compute drain across all six tower pairs
BV_KEYREUSE_DRAIN_OVERLAP_SIM_RUN_END

PASS: exact coefficient-major compute-drain overlap checkpoint complete
```

The board runner's `estimated_serialized_schedule_efficiency` field is stale
for ping-pong hardware. Values above 100% do not represent impossible
performance; the denominator still includes output cycles that are now
overlapped.
