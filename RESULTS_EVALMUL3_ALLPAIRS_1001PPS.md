# Exact all-pair EvalMultNoRelin result

## Configuration

| Item | Value |
| --- | ---: |
| Board | PYNQ-Z2 |
| FPGA | XC7Z020-1 |
| OpenFHE scheme | BGVRNS |
| Ring dimension | 4096 |
| Q towers | 12 |
| Paired passes | 6 |
| Ciphertexts | 64 |
| Core clock | 100 MHz |
| DMA/HP clock | 150 MHz |

## Board output

```text
run=0 exact elapsed_us=63947.93
run=1 exact elapsed_us=64087.69
run=2 exact elapsed_us=63927.73
run=3 exact elapsed_us=63879.59
run=4 exact elapsed_us=63869.55
run=5 exact elapsed_us=63903.75
run=6 exact elapsed_us=63859.14

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

## Improvement from the prior batch-64 path

| Metric | Six transactions | One EV12 transaction | Change |
| --- | ---: | ---: | ---: |
| Compute latency | 1122.52 us/ct | 998.50 us/ct | -11.05% |
| Compute throughput | 890.86/s | 1001.51/s | +12.42% |

## Physical result

```text
implementation_strategy=Performance_ExplorePostRoutePhysOpt
EVALMUL3_ALLPAIRS_WNS_NS=0.027
EVALMUL3_ALLPAIRS_FAILING_PATHS=0
EVALMUL3_ALLPAIRS_LUTS=8507
EVALMUL3_ALLPAIRS_REGISTERS=9846
EVALMUL3_ALLPAIRS_DSP48E1=128
EVALMUL3_ALLPAIRS_RAMB18E1=4
EVALMUL3_ALLPAIRS_RAMB36E1=4
PASS: all-pair evaluation-domain dual-clock DMA overlay routed
```
