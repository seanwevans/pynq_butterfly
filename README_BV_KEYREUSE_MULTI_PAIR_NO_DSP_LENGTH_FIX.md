# Multi-pair session no-DSP protocol-length fix

Vivado synthesized the exact arithmetic child plus session wrapper as:

```text
expected DSP48E1: 160
actual DSP48E1:   164
```

The extra four DSPs came from protocol bookkeeping in the wrapper:

```systemverilog
frame_digit_count * (frame_batch_count + 2)
```

Because both operands had been widened to 64 bits, Vivado mapped the dynamic
length calculation into four DSP48E1 cells. These cells do not perform
cryptographic arithmetic.

## Fix

The wrapper now computes:

```text
digit_count × (batch_count + 2)
```

with an explicit five-bit shift-add network. It also replaces multiplication by
`N` with a constant left shift:

```text
pair_payload_words = words_per_coefficient << $clog2(N)
```

The supported configurations already satisfy the required bounds:

```text
simulation: N=32
production: N=4096
MAX_BATCH=64
MAX_DIGITS=16
```

No stream protocol, arithmetic result, output ordering, or timing schedule is
changed.

## Apply and rerun exact simulation

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_multi_pair_session_no_dsp_length_fix.zip

./run_bv_keyreuse_multi_pair_session_checkpoint.sh
```

Expected exact ending:

```text
MULTI_PAIR_SESSION_OUTPUT_WORDS=3072
MULTI_PAIR_SESSION_INTERMEDIATE_TLAST_SUPPRESSED=5
PASS: exact six-pair persistent-output session matches OpenFHE
PASS: exact persistent-output multi-pair session checkpoint complete
```

## Rerun OOC timing sweep

```bash
./build_bv_keyreuse_multi_pair_session_ooc_timing_sweep.sh
```

Expected synthesis gate:

```text
BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_SYNTH_DSP48E1=160
```

The OOC build still rejects any result other than exactly 160 DSP48E1.
