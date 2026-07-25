# Icarus packed-array elaboration fix

The OpenFHE evaluation-domain gate passed. Icarus then rejected two procedural
loops that used integer variables to select slices of packed multidimensional
arrays:

```text
Array index expressions must be constant here
```

Vivado accepts that SystemVerilog form, but Icarus requires those two-tower
selects to be statically elaborated.

This patch explicitly unrolls:

- the lane-0/lane-1 input operand wiring;
- the lane-0/lane-1 `c1 = p01 + p10 mod q` reduction.

The generated circuit is unchanged.

Apply from the repository root:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_iverilog_unroll_fix.zip

./scripts/sim/run_evalmul3_two_tower_axis_sim.sh
```

Then rerun both gates:

```bash
./run_eval_domain_fused_checkpoint.sh 12 4
```
