# N=4096 four-butterfly memory checkpoint

This checkpoint proves the memory geometry required to issue four NTT
butterflies per polynomial in each schedule group.

Bank mapping:

    bank[0] = parity(address bits 0, 3, 6, 9)
    bank[1] = parity(address bits 1, 4, 7, 10)
    bank[2] = parity(address bits 2, 5, 8, 11)

Row mapping:

    row = address[11:3]

The combined `(row, bank)` mapping is a bijection over all 4096 logical
coefficient addresses.

For each stage bit `s`, the schedule chooses two grouping bits from the
other parity classes. Toggling the three bits spans all eight banks and
therefore forms four conflict-free butterflies.

Expected schedule geometry:

    4 butterflies/group
    8 coefficients/group
    512 groups/stage
    12 stages/transform
    6144 groups/transform

Expected store synthesis:

    8 RAMB18
    0 RAMB36
    4 BRAM tile equivalents
    0 DSP
