# Four-wide handoff read-collision fix

The first four-wide simulation failed at coefficient 28.

Cause: the arithmetic handoff core still expressed a four-wide result capture
as an ordinary eight-wide coefficient-store read of `base..base+7`, then kept
only lanes 0..3. That is safe only when the eight addresses map to eight unique
XOR banks. At base 28, addresses 28..35 cross a bank-permutation boundary and
collide, corrupting coefficient 28.

This patch adds a true four-wide handoff read port. It requests only
`base..base+3`, which is conflict-free for every four-aligned base.

The schedule remains:

```text
22,968 arithmetic clocks
 1,025 four-wide handoff clocks
-------------------------------
23,993 clocks/product
```

Apply:

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o poly_mul4096_four_butterfly_buffered4_readfix.zip
./scripts/synth/compile_poly_mul4096_four_butterfly_two_tower_buffered_axis.sh
```
