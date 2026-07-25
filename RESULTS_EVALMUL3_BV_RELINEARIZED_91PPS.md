# Exact fused OpenFHE BV relinearization on PYNQ-Z2

## Functional proof

The host-decomposed fused RTL exactly matched OpenFHE 1.5.1:

```text
technique=BV
q_towers=12
p_towers=0
digits=12
max_q_modulus_bits=30

pair_count=6
coefficient_count=32
expected_words=384

PASS: exact fused EvalMul3 plus BV relinearization across all six tower pairs
PASS: exact fused OpenFHE BV relinearization RTL checkpoint complete
```

The FPGA arithmetic is:

```text
c0 = a0*b0
c1 = a0*b1 + a1*b0
c2 = a1*b1

ks_b = sum_j digit_j * eval_key_b_j mod q
ks_a = sum_j digit_j * eval_key_a_j mod q

relin_c0 = c0 + ks_b mod q
relin_c1 = c1 + ks_a mod q
```

BV decomposition digits are supplied by the host.

## Physical implementation

### Standalone fused core

```text
clock=100 MHz
WNS=+0.016 ns
failing_paths=0
LUTs=8112
registers=6775
DSP48E1=192
BRAM=0
```

### Dual-clock DMA overlay

```text
core/control=100 MHz
DMA/HP/SmartConnect=150 MHz
WNS=+0.045 ns
failing_paths=0
LUTs=11746
registers=11875
DSP48E1=192
RAMB18E1=4
RAMB36E1=4
bitstream=complete
HWH=complete
```

## Board result

```text
PASS: every fused RLBV relinearized component matches OpenFHE
towers=12
pairs=6
digits=12
ciphertexts=8
words_per_coefficient=40
send_bytes_per_pair=10485776
receive_bytes_per_pair=524288
total_input_bytes_per_run=62914656
total_output_bytes_per_run=3145728
maximum_ciphertexts_per_pair_frame=51
median_profile_us=3171.18
median_data_us=84297.06
median_total_us=87552.52
stream_efficiency=93.2929%
verified_tower_components=192
data_us_per_relinearized_EvalMult=10537.13
data_relinearized_EvalMult_per_second=94.90
end_to_end_us_per_relinearized_EvalMult=10944.06
end_to_end_relinearized_EvalMult_per_second=91.37
```

The input-limited ideal for this protocol is:

```text
983040 cycles/ciphertext
9830.4 us/ciphertext
101.725 relinearized EvalMult/s
```

The measured data path reaches 93.29% of that ceiling.
