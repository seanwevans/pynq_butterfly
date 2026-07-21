# Four-butterfly two-tower PYNQ-Z2 overlay

This is the first actual-board checkpoint for the new arithmetic core.

It uses:

- both RNS towers concurrently
- four pipelined butterflies per tower
- 22,968 arithmetic clocks per product
- 128 DSP48E1
- 64-bit AXI DMA
- exact OpenFHE q0/q1 vectors

This checkpoint deliberately uses direct product streaming rather than
prefetch/handoff buffering. It validates the new core through PS, DDR,
AXI DMA, packaged IP, bitstream, and the physical PYNQ-Z2 before overlap
logic is added.

## 1. Install the drop

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o ./poly_mul4096_four_butterfly_board_overlay.zip
```

## 2. Simulate the AXI adapter

```bash
./compile_poly_mul4096_four_butterfly_two_tower_axis.sh
```

Expected ending:

```text
PASS: direct 64-bit AXI frame produced exact q0/q1 OpenFHE result
PASS: checked 4096 paired output coefficients
Core cycles per two-tower product: 22968
```

## 3. Package IP and build the PYNQ-Z2 overlay

```bash
./build_poly_mul4096_four_butterfly_two_tower_board.sh
```

The deployable directory will be:

```text
deploy/poly_mul4096_four_butterfly_two_tower_dma/
```

The integration requires nonnegative WNS before copying deployment artifacts.

## 4. Copy to the board

Using the board hostname:

```bash
./install_poly_mul4096_four_butterfly_two_tower_board.sh pynq
```

Using an IP address:

```bash
./install_poly_mul4096_four_butterfly_two_tower_board.sh 192.168.2.99
```

## 5. Run on the PYNQ-Z2

```bash
ssh xilinx@pynq
cd /home/xilinx/jupyter_notebooks/p4tt
chmod +x run_poly_mul4096_four_butterfly_two_tower_board.sh
./run_poly_mul4096_four_butterfly_two_tower_board.sh
```

The board test loads both runtime profiles, runs one exact validation product,
then runs 20 timed products and reports physical throughput.

## Protocol change

The profile frame contains one new word after the modulus pair:

```text
paired Barrett reciprocals floor(2^60 / q)
```

Profile frame length is therefore 16,385 64-bit words rather than 16,384.
