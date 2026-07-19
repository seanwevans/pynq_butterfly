# OpenFHE one-tower FPGA bridge

This checkpoint sends a real one-tower OpenFHE `DCRTPoly` multiplication
through the PYNQ-Z2 N=4096 two-bank accelerator.

Profile:

- ring dimension: 4096
- cyclotomic order: 8192
- modulus: 1073692673
- root of unity: 236231
- coefficient encoding: unsigned 32-bit little-endian
- DMA input: A followed by B, 8192 words / 32768 bytes
- DMA output: C, 4096 words / 16384 bytes

`openfhe_tower_bridge generate` creates coefficient-format OpenFHE
`DCRTPoly` operands, switches copies into evaluation format, multiplies
them using OpenFHE, returns the product to coefficient format, and exports
the exact DMA input and expected result.

`openfhe_tower_bridge verify` reconstructs the operands from the
transmitted DMA bytes, recomputes the product with OpenFHE, imports the
FPGA result into a `DCRTPoly`, and requires object-level equality.
