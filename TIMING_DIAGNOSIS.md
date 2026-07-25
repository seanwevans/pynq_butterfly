# Timing diagnosis

Worst path:

```text
Source:
    bv_meta_read_pointer_reg[0]

Destination:
    ks_a_memory_bank0 distributed-RAM write input

Slack:
    -0.017 ns

Data path:
    9.052 ns
    logic 3.857 ns
    route 5.195 ns
    14 logic levels
```

The second reported path has the same structure through `ks_b_memory_bank0`.
The violations are accumulator read-modify-write paths.
