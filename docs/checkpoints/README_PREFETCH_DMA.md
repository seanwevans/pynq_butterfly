# One-product operand-prefetch physical overlay

This bundle packages the proven prefetch wrapper as:

    user.org:user:db2p:1.0

The short Vivado project is:

    F:\v\db2p

The arithmetic core remains 631810 clocks per product. For each
nonfinal product, result output and same-address shadow-to-core refill
take 8193 clocks. The resulting steady-state product spacing is:

    640003 clocks
    6400.03 us at 100 MHz

Expected accelerator storage:

    64 RAMB36

Expected complete overlay storage:

    66 RAMB36 + 2 RAMB18

The board test reuses the existing sixteen distinct OpenFHE products and
measures batch counts 1, 2, 4, 8, and 16.
