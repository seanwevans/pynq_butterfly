# EvalMul3 batch-scaling result

All four batch sizes matched OpenFHE exactly.

```text
batch   compute us/ct   compute ct/s   efficiency
32          1203.26          831.07       81.7%
64          1122.52          890.86       87.6%
128         1080.04          925.90       91.1%
256         1057.98          945.20       92.9%
```

A least-squares fit over the mean six-pair medians is:

```text
T_pair(B) = 903.14 us + 172.8326 us * B
```

Equivalently, for a complete twelve-tower ciphertext:

```text
T_compute(B) = 1036.996 us + 5418.86 us / B
```

The fitted large-batch limit is therefore:

```text
964.32 EvalMultNoRelin/s
```

The ideal 100 MHz stream limit is:

```text
983.04 us/ciphertext
1017.25 EvalMultNoRelin/s
```

Conclusion:

- roughly 903 us per tower-pair transaction is fixed DMA/software overhead;
- sustained transfer efficiency is about 94.8%;
- larger batches alone cannot reach 1,000 ciphertexts/s;
- reaching 1,000 requires recovering about 3.7% of sustained stream bandwidth.

The next overlay keeps the arithmetic core at 100 MHz while moving DMA and the
two PS HP ports to 150 MHz. Two 1024-word asynchronous AXI4-Stream clock
converters buffer the fast memory side against the 100 MHz core. DRE is removed
because every tested PYNQ buffer address and transfer length is 64-bit aligned.
The DMA burst length remains 16 beats because that is the Zynq-7000 HP-port
maximum.
