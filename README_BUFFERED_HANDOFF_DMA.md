# Buffered-handoff physical overlay

This bundle packages the proven four-wide handoff wrapper as:

    user.org:user:db2r:1.0

The short Vivado project is:

    F:\v\db2r

The arithmetic core remains 631810 clocks per product. Each nonfinal
product uses a 1025-clock four-wide handoff into one result buffer per
tower while refilling the arithmetic stores from the prefetched operand
stores.

Steady-state spacing:

    632835 clocks
    6328.35 us at 100 MHz

Expected accelerator storage:

    72 RAMB36

Expected complete overlay storage:

    74 RAMB36 + 2 RAMB18

The board test reuses the existing sixteen distinct OpenFHE products and
measures batch counts 1, 2, 4, 8, and 16.
