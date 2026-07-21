"""Shared constants for the N=4096 two-tower overlay board tests.

These values are fixed by the RTL stream protocol and the dual-butterfly
arithmetic schedule. They previously appeared as independent literals in
every board test script; the RTL remains the authority, and this module
is the single Python copy.

When deploying a test script to the board, copy this file alongside it.
"""

# Ring dimension of Z_q[X]/(X^4096 + 1) and the compact twiddle count.
N = 4096
TWIDDLE_WORDS = N - 1

# 32-bit stream command words (ASCII "PROF", "MUL1", "MULB").
PROFILE_COMMAND_WORD = 0x50524F46
PRODUCT_COMMAND_WORD = 0x4D554C31
BATCH_COMMAND_WORD = 0x4D554C42

# One profile lane: command word, modulus word, then the payload of
# twist factors, forward twiddles, inverse twiddles, and inverse scale
# factors.
PROFILE_PAYLOAD_WORDS = N + TWIDDLE_WORDS + TWIDDLE_WORDS + N
PROFILE_LANE_WORDS = 2 + PROFILE_PAYLOAD_WORDS

# One product lane: command word, then operand A and operand B.
PRODUCT_LANE_WORDS = 1 + 2 * N
RESULT_LANE_WORDS = N

# Dual-butterfly arithmetic core (timing-isolated schedule).
DUAL_BUTTERFLY_CORE_CYCLES = 631_810
HANDOFF_CYCLES_PER_NONFINAL_PRODUCT = 1_025
STEADY_STATE_CYCLES_PER_PRODUCT = (
    DUAL_BUTTERFLY_CORE_CYCLES + HANDOFF_CYCLES_PER_NONFINAL_PRODUCT
)

# Single-butterfly runtime-profile core, as shipped in the parallel
# two-tower and runtime-profile overlays.
SINGLE_BUTTERFLY_CORE_CYCLES = 1_339_394

# Programmable-logic clock for every overlay in this repository.
CLOCK_MHZ = 100.0
