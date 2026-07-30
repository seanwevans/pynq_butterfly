# Timing-isolated two-tower DMA rebuild

The standalone timing-isolated core now closes synthesis timing at:

    WNS = +0.706 ns
    48 RAMB36
    0 DSP
    631810 clocks
    6318.10 us at 100 MHz

This bundle republishes the modified RTL as short-named IP
`user.org:user:db2ti:1.1` and rebuilds the complete PYNQ-Z2 DMA overlay
under `F:\v\db2ti` to avoid Windows path-length failures.

The integration strategy is:

    Performance_ExplorePostRoutePhysOpt

The deployment directory remains:

    F:\repos\pynq_butterfly\deploy\
        poly_mul4096_dual_butterfly_two_tower_dma
