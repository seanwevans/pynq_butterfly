# DSP diagnosis

Observed:

```text
BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_SYNTH_DSP48E1=164
```

Known arithmetic child:

```text
10 Barrett pipelines × 16 DSP48E1 = 160 DSP48E1
```

Wrapper-only dynamic arithmetic:

```systemverilog
{32'd0, frame_digit_count}
*
({32'd0, frame_batch_count} + 64'd2)
```

Vivado inferred exactly four additional DSP48E1 cells from that widened
protocol-length multiplication.

The replacement contains no multiplication operator in the synthesizable
payload-length datapath.
