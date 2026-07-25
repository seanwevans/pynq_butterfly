# Buffered four-butterfly write-locality timing fix

The first physical buffered build routed at WNS -0.606 ns. The worst paths
start at the normal arithmetic writeback metadata and terminate at arithmetic
coefficient-store RAM write data/address pins. They are approximately
88 percent routing delay.

The first handoff generator inserted a centralized effective-write mux between
the already-proven arithmetic writeback logic and both eight-bank coefficient
stores. That wide mux created high-fanout cross-device nets such as
`a_store_effective_write_address`.

This patch removes that centralized mux.

A dedicated handoff-capable coefficient-store wrapper now accepts the original
arithmetic write buses unchanged and selects the idle-only handoff source inside
the store hierarchy. The eight small write selections can therefore be placed
beside their destination BRAM banks.

No clock is added:

- arithmetic remains 22,968 cycles;
- handoff remains 513 cycles;
- steady cadence remains 23,481 cycles/product.

## Apply

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o poly_mul4096_buffered_write_locality_fix.zip
```

## Revalidate exact simulation

```bash
./compile_poly_mul4096_four_butterfly_two_tower_buffered_axis.sh
```

Expected ending is unchanged:

```text
PASS: 4 buffered exact two-tower OpenFHE products
PASS: eight-wide result/refill handoff = 513 clocks
PASS: operand prefetch and compute/output overlap observed
Steady hardware cadence: 23481 cycles/product
```

## Rebuild

```bash
./build_poly_mul4096_four_butterfly_two_tower_buffered_board.sh
```

The board build still rejects negative WNS.
