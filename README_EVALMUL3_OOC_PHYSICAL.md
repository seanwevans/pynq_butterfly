# Fused evaluation-domain OOC physical checkpoint

The software and RTL functional checkpoint passed:

```text
PASS: fused components equal OpenFHE EvalMultNoRelin
PASS: fused two-tower evaluation-domain c0/c1/c2 exact
PASS: deterministic AXI output backpressure tolerated
```

This checkpoint performs a complete out-of-context implementation of:

```text
evalmul3_two_tower_axis_core
```

for the PYNQ-Z2 FPGA:

```text
part        xc7z020clg400-1
clock       100 MHz
Vivado      2024.1 by default
threads     1
```

It runs:

```text
synthesis
optimization
placement
physical optimization
routing
post-route physical optimization
timing, DRC, and utilization reports
```

The build fails unless routed WNS is nonnegative.

## Apply

From the repository root:

```bash
cd /mnt/f/repos/pynq_butterfly

unzip -o \
  evalmul3_ooc_physical_checkpoint.zip
```

The corrected Icarus-compatible RTL is included again and may overwrite the
same file with identical content.

## Run

```bash
./scripts/vivado/build_evalmul3_ooc.sh
```

Default locations:

```text
Vivado:
  /mnt/f/Xilinx/Vivado/2024.1/bin/vivado.bat

Build:
  /mnt/f/v/evalmul3_ooc
```

Overrides:

```bash
VIVADO_BAT=/mnt/f/Xilinx/Vivado/2024.1/bin/vivado.bat \
EVALMUL3_OOC_WORK=/mnt/f/v/evalmul3_ooc \
./scripts/vivado/build_evalmul3_ooc.sh
```

The shell script invokes the Windows `.bat` through a generated `.cmd` and
`cmd.exe /d /c`; it does not attempt to execute the batch file directly under
Bash.

## Expected architecture

There are eight Barrett multiplier pipelines:

```text
two RNS towers
× four products per coefficient
= eight multiplier pipelines
```

The existing Barrett implementation used by this core has seven-cycle
latency and initiation interval one. Based on the already measured
four-lane engine, the expected DSP usage is approximately 128 DSP48E1 blocks,
well within the XC7Z020 total of 220.

The core intentionally contains no:

```text
coefficient BRAM
twiddle BRAM
forward NTT
inverse NTT
```

## Success output

```text
EVALMUL3_OOC_WNS_NS=<nonnegative>
EVALMUL3_OOC_FAILING_PATHS=0
EVALMUL3_OOC_DSP48E1=<count>
PASS: fused evaluation-domain core routed at 100 MHz
```

After this passes, the next drop will package the core into the existing
AXI-DMA block design, generate `.bit` and `.hwh`, and run the physical
OpenFHE `EVB3` benchmark.
