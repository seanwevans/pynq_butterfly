# Reproducible benchmark summary

The current headline measurement uses `N=4096`, 12 Q towers, 12 BV digits, and
batches of 64 ciphertexts. The persistent six-pair session measures 4,071.50 us
per ciphertext, or 245.61 exact relinearized ciphertexts/s, with 6,291,456
residue words checked and zero mismatches.

The FPGA number is a median of repeated no-copy session-wall runs. Host BV CRT
decomposition, initial packing, key generation, and encryption are outside the
timed region. Consequently the comparison with the 244.87 ciphertexts/s
single-call OpenFHE reference should be read as parity, not a demonstrated win.

The detailed current evidence is in
[`results-first-b64-multi-pair-session.md`](results-first-b64-multi-pair-session.md)
and [`results-bv-keyreuse-multi-pair-session-dma150.md`](results-bv-keyreuse-multi-pair-session-dma150.md).
All other result files preserve reproducible measurements from earlier designs.
