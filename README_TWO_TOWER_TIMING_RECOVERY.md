# Two-tower timing-recovery sweep

The first two-tower implementation missed 100 MHz by 75 ps:

```text
WNS = -0.075 ns
```

The critical path remained inside a single Barrett multiplier lane, indicating
placement/routing congestion rather than a cross-tower logic problem.

This checkpoint resynthesizes once and explores five Vivado 2024.1
implementation strategies from the same synthesis checkpoint:

1. `Performance_Explore`
2. `Performance_ExploreWithRemap`
3. `Performance_WLBlockPlacement`
4. `Performance_ExtraTimingOpt`
5. `Congestion_SpreadLogic_high`

For each strategy it records routed and post-route-physical-optimization WNS,
then preserves the best routed DCP.

No RTL or arithmetic latency changes are made.

## Install

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o ./poly_mul4096_two_tower_timing_recovery.zip
```

## Run

```bash
./recover_poly_mul4096_four_butterfly_two_tower_timing.sh
./check_poly_mul4096_four_butterfly_two_tower_timing.py
```

Results are written under:

```text
reports/poly_mul4096_four_butterfly_two_tower_timing_recovery/
```

The best checkpoint is:

```text
reports/poly_mul4096_four_butterfly_two_tower_timing_recovery/best/routed.dcp
```

A positive result permits continuation to the AXI/IP/board overlay. If every
strategy remains negative, the Barrett multiplier receives one additional
pipeline split before board integration.
