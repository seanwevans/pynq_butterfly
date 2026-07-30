# Persistent-output multi-pair session OOC timing sweep

Exact simulation passed:

```text
3072 exact output words
5 intermediate child TLAST markers suppressed
400 deterministic output-backpressure cycles
0 mismatches
```

The nonfatal Icarus warning:

```text
@* is sensitive to all 2 words in array 'payload_data'
```

is expected for the combinational read of the two-entry registered payload
FIFO. The exact simulation completed successfully.

This checkpoint measures the physical cost of:

```text
six-entry paired-tower profile table
RLPT/RLMP session parser
child RLPF/RLCM header injection
two-entry registered payload FIFO
persistent output session state
five intermediate output-TLAST suppressions
```

The arithmetic child remains the exact 160-DSP drain-overlap core.

## Apply and run

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_multi_pair_session_ooc_timing_sweep.zip

./scripts/vivado/build_bv_keyreuse_multi_pair_session_ooc_timing_sweep.sh
```

Output:

```text
/mnt/f/v/bv_keyreuse_multi_pair_session_ooc_timing_sweep
```

The same post-synthesis checkpoint is tried with:

```text
ExploreWithRemap
RemapNetDelayHigh
DefaultExplore
ExplorePostRoutePhysOpt
ExploreNetDelayHigh
```

Expected ending:

```text
BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_SYNTH_DSP48E1=160
STRATEGY_..._ROUTE_WNS_NS=...
STRATEGY_..._POST_PHYS_WNS_NS=...
BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_BEST_STRATEGY=...
BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_BEST_STAGE=...
BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_WNS_NS=...
BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_FAILING_PATHS=0
BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_DSP48E1=160
PASS: persistent-output multi-pair session core routed at 100 MHz
```

Best checkpoint:

```text
/mnt/f/v/bv_keyreuse_multi_pair_session_ooc_timing_sweep/best_routed.dcp
```
