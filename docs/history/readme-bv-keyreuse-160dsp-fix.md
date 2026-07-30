# 160-DSP synthesis correction

The physical run stopped after synthesis with:

```text
BV_KEYREUSE_COEFFICIENT_MAJOR_OOC_SYNTH_DSP48E1=160
FAIL: synthesis did not preserve exactly 192 DSP48E1
```

This is not a lost arithmetic path. It is the correct architecture.

The coefficient-major core instantiated twelve Barrett pipelines:

```text
c0:        a0*b0             2 lanes
c1 term 1: a0*b1             2 lanes
c1 term 2: a1*b0             2 lanes
c2:        a1*b1             2 lanes
BV ks_b:   digit*key_b        2 lanes
BV ks_a:   digit*key_a        2 lanes
                              -------
                              12 pipelines
```

But this checkpoint receives host-generated BV decomposition digits. Nothing
consumes `c2`, so Vivado correctly removed its two Barrett pipelines:

```text
10 live pipelines * 16 DSP48E1 = 160 DSP48E1
```

This patch removes the unused c2 pipelines explicitly and changes the physical
gate from 192 to 160 DSP48E1. Functional output is unchanged.

The resulting design frees 32 DSP48E1, leaving 60 of the Zynq-7020's 220 DSPs
available for later decomposition or overlap work.

## Apply and rerun

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_bv_keyreuse_160dsp_synthesis_fix.zip

./scripts/vivado/build_bv_keyreuse_coefficient_major_ooc.sh
```

Expected synthesis line:

```text
BV_KEYREUSE_COEFFICIENT_MAJOR_OOC_SYNTH_DSP48E1=160
```

The build should then continue through placement and routing.
