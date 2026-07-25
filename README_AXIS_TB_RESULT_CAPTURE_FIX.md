# AXI testbench result-capture fix

The watchdog proved that both towers completed in 22,968 clocks and the AXI
output FSM emitted the result. The sequential checker started too late, after
all output handshakes had already occurred.

This patch:

- replaces the complete `send_word` task;
- samples `TREADY` before the accepting edge;
- holds `M_AXIS_TREADY=0` while transmitting the product;
- releases output backpressure immediately before the checking loop.

Apply from the repository root:

```bash
unzip -o ./poly_mul4096_axis_tb_result_capture_fix.zip
./apply_poly_mul4096_axis_tb_result_capture_fix.sh
```
