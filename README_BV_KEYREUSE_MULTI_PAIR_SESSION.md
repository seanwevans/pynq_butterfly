# Persistent-output multi-pair session checkpoint

The drain-overlap board sweep produced a nearly constant data-time overhead:

```text
batch  overhead above input floor
8      5347.62 us
16     5359.10 us
32     5359.69 us
64     5358.56 us
```

Mean:

```text
5356.24 us
```

Range across the entire B8–B64 sweep:

```text
12.07 us
```

That is strong evidence that the remaining gap is fixed six-pair transaction
overhead rather than batch-dependent arithmetic or stream throughput.

At B64:

```text
measured FPGA data rate: 243.42/s
OpenFHE reference rate:   about 244.87/s
gap:                      0.59%
time reduction required:  1553.12 us per 64-ciphertext run
```

## Architecture tested here

This wrapper stores all six paired-tower profiles and creates a session whose
output has exactly one external TLAST.

The host can arm one S2MM receive transfer for all six pair outputs, then submit
six legal MM2S pair frames. Each input frame remains below the AXI DMA's
26-bit length limit, including B64. Intermediate child-core output TLAST
markers are suppressed.

Commands:

```text
RLPT = 0x524c5054   paired-tower profile table
RLMP = 0x524c4d50   one pair inside a persistent output session
```

Profile table:

```text
{RLPT,RLPT}
{pair_count,pair_count}
q/mu words for every pair
```

Pair frame:

```text
{RLMP,RLMP}
{digit_count,ciphertext_count}
{pair_count,pair_index}
coefficient-major RLCM payload
```

## Apply and simulate

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_multi_pair_session_exact_sim_checkpoint.zip

./run_bv_keyreuse_multi_pair_session_checkpoint.sh
```

Coverage:

```text
6 paired Q-tower profiles
6 independently terminated input pair frames
1 persistent external output frame
12 BV digits
8 ciphertexts
32 coefficients
3072 exact output words
deterministic output backpressure
5 intermediate child TLAST markers suppressed
```

Expected ending:

```text
MULTI_PAIR_SESSION_OUTPUT_WORDS=3072
MULTI_PAIR_SESSION_INTERMEDIATE_TLAST_SUPPRESSED=5
MULTI_PAIR_SESSION_OUTPUT_BACKPRESSURE_CYCLES=...
PASS: exact six-pair persistent-output session matches OpenFHE
BV_KEYREUSE_MULTI_PAIR_SESSION_SIM_RUN_END

PASS: exact persistent-output multi-pair session checkpoint complete
```

This checkpoint does not yet claim a board speedup. It tests the exact stream
semantics needed to remove five of the six S2MM transfer launches while
respecting the B64 MM2S length limit.
