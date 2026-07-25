# AXI testbench handshake fix

The accelerator accepted the final B word correctly. The testbench then checked
`TREADY` after that edge, by which time the FSM had legally deasserted it. The
send task blocked through computation while the ready output stream was consumed,
then began checking output only after the result frame had passed.

Apply and rerun:

```bash
cd /mnt/f/repos/pynq_butterfly
unzip -o ./poly_mul4096_axis_tb_handshake_fix.zip
./apply_poly_mul4096_axis_tb_handshake_fix.sh
```
