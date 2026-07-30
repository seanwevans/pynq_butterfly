# Stream protocol

The supported overlay transfers two adjacent Q towers in each 64-bit AXI4-Stream
word, with the lower-numbered tower in bits 31:0. A session begins with one
`RLPT` profile-table frame and processes six indexed `RLMP` paired-tower frames
under one persistent S2MM receive. Only the sixth child operation emits the
external `TLAST`.

Payloads are pair-major, coefficient-major, then ciphertext-major. Results use
the same ordering and emit `relin_c0` followed by `relin_c1`. The normative word
layout, counts, and state transitions are in
[`session-protocol.md`](session-protocol.md).
