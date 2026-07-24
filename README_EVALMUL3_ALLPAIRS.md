# EvalMul3 all-pair 1001 pps checkpoint

This checkpoint replaces six software-visible pair transactions with one
logical `EV12` transaction covering all 12 OpenFHE RNS towers.

## Exact board result

PYNQ-Z2, OpenFHE BGVRNS, `N=4096`, 12 towers, batch 64:

```text
PASS: every EV12 fused evaluation-domain component matches OpenFHE
towers=12
pairs=6
ciphertexts=64
send_bytes=50331664
receive_bytes=37748736
profile_table_us=524.17
warmup_us=63847.77
median_us=63903.75
stream_efficiency=98.4521%
verified_tower_components=2304
compute_us_per_EvalMultNoRelin=998.50
compute_EvalMultNoRelin_per_second=1001.51
end_to_end_us_per_EvalMultNoRelin=1006.69
end_to_end_EvalMultNoRelin_per_second=993.36
```

The steady-state compute result exceeds 1,000 exact encrypted
`EvalMultNoRelin` operations per second at batch 64. The prior dual-clock
batch-64 path required six DMA transactions and achieved 890.86/s.

## Physical implementation

```text
Vivado 2024.1
XC7Z020-1
core clock:     100 MHz
DMA/HP clock:   150 MHz
strategy:       Performance_ExplorePostRoutePhysOpt
WNS:            +0.027 ns
failing paths:  0
LUTs:           8507
registers:      9846
DSP48E1:        128
RAMB18E1:       4
RAMB36E1:       4
```

## Protocol

`EVPT` (`0x45565054`) loads up to six paired-tower `{q, mu}` profiles.

`EV12` (`0x45563132`) carries one pair-major batch for all loaded pairs. The
sequencer internally presents the proven `EVPF`/`EVB3` protocol to the
two-tower arithmetic core and suppresses intermediate output `TLAST` markers.

## Exact RTL checkpoint

```bash
./run_evalmul3_allpairs_checkpoint.sh
```

The test covers three tower pairs, two ciphertexts, exact paired-lane
`c0/c1/c2`, and deterministic output backpressure.

## Physical build

```bash
./build_evalmul3_allpairs_dma150_overlay.sh
```

## Board installation and run

```bash
./install_evalmul3_allpairs_board.sh \
  openfhe_eval_domain_bridge/vectors/t12_c384 \
  xilinx@pynq \
  /home/xilinx/jupyter_notebooks/evalmul3_allpairs
```

On the board:

```bash
sudo -i

/home/xilinx/jupyter_notebooks/evalmul3_allpairs/run_evalmul3_allpairs_board.sh \
  /home/xilinx/jupyter_notebooks/evalmul3_allpairs \
  64 \
  7
```

A very large contiguous XRT allocation can fail after long board uptime due to
CMA fragmentation. A fresh boot successfully allocated the 48 MiB input and
36 MiB output buffers used by this checkpoint.
