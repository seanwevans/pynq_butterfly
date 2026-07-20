# N=4096 four-butterfly cyclic NTT checkpoint

This checkpoint integrates the proven eight-bank coefficient store with
four timing-isolated radix-2 butterfly lanes and four simultaneous
twiddle reads.

Transform modes:

- forward DIF: stages 11 through 0
- inverse DIT: stages 0 through 11
- inverse transform is intentionally unscaled

Exact target:

    4 butterflies/group
    512 groups/stage
    12 stages/transform
    6144 groups/transform
    24576 butterflies/transform
    141313 clocks/transform

The four-read twiddle table consists of two identical dual-read XPM
tables. Runtime writes update both copies.

Expected standalone memory:

    coefficient store: 8 RAMB18
    twiddle copies:     8 RAMB36
    DSP:                0

The functional regression checks q0 and q1 forward outputs against a
software DIF model, then checks that inverse DIT returns N times each
original input.
