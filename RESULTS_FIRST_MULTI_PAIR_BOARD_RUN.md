# First persistent-output board result

```text
B8 exact
dma_call_us=40548.00
session_wall_us=32187591.61
host packing gap=32147033.40
dma-call throughput=197.30/s
```

The 32-second wall time was caused by five nested-Python frame builds performed
after S2MM was armed. The prepacked runner removes that work from the session.
