# Arbitrary-batch physical sweep

This checkpoint uses the existing timing-clean batch bitstream unchanged.

It generates sixteen distinct two-tower OpenFHE products by repeatedly
calling the already-proven batch-of-two vector generator. The board benchmark
then measures batch counts:

```text
1, 2, 4, 8, 16
```

The q0/q1 runtime profile is loaded exactly once. Every first and timed result
is checked coefficient-for-coefficient against its distinct OpenFHE product.

Largest transfer sizes:

```text
batch-16 input:  1,048,592 bytes
batch-16 output:   524,288 bytes
```

These are well below the overlay's 26-bit AXI DMA length limit.

The benchmark writes:

```text
batch_sweep.csv
batch_sweep.json
batchN/fpga_productK_tower0.bin
batchN/fpga_productK_tower1.bin
```

No RTL, IP packaging, Vivado implementation, or bitstream change is required.
