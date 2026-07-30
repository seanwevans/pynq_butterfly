# First B64 persistent-output result

```text
exact residue words:       6291456
send mode:                 reuse-copy
DMA-call interval:         261731.38 us
DMA-call throughput:       244.53/s
copy/flush interval:       532602.66 us
session wall interval:     794850.65 us
session wall throughput:   80.52/s
```

Compared with the previous six-S2MM drain-overlap implementation:

```text
262915.04 us -> 261731.38 us
1183.66 us reduction
243.42/s -> 244.53/s
```
