#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import statistics
import time
from pathlib import Path

import numpy as np
from pynq import Overlay, allocate


N = 4096

PROFILE_TABLE_COMMAND = np.uint32(0x524C5054)  # RLPT
MULTI_PAIR_COMMAND = np.uint32(0x524C4D50)    # RLMP

DIGIT_COUNT_EXPECTED = 12
PAIR_COUNT_EXPECTED = 6
MAX_BATCH = 64

CLOCK_HZ = 100_000_000
DMA_LENGTH_WIDTH = 26
MAX_DMA_BYTES = (1 << DMA_LENGTH_WIDTH) - 1

EVAL_WORDS_PER_CIPHERTEXT = 4
KEY_WORDS_PER_DIGIT = 2
DIGIT_WORDS_PER_CIPHERTEXT = 1
OUTPUT_WORDS_PER_CIPHERTEXT = 2

# The drain-overlap core begins the next coefficient immediately after the
# current coefficient's final input word. Its steady-state lower bound is
# therefore the input stream itself: 16*B+24 words per coefficient for D=12.


def read_json(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def tower_name(index: int) -> str:
    return f"tower{index:03d}"


def digit_name(index: int) -> str:
    return f"digit{index:03d}"


def read_u64le(path: Path, expected_words: int) -> np.ndarray:
    values = np.fromfile(
        path,
        dtype="<u8",
        count=expected_words,
    )

    if values.size != expected_words:
        raise ValueError(
            f"{path}: found {values.size} words; "
            f"expected {expected_words}"
        )

    return np.asarray(values, dtype=np.uint64)


def read_tower_u32(
    root: Path,
    tower_index: int,
) -> np.ndarray:
    values = read_u64le(
        root / f"{tower_name(tower_index)}.u64le.bin",
        N,
    )

    if np.any(values > np.uint64(0xFFFFFFFF)):
        bad = int(
            np.flatnonzero(
                values > np.uint64(0xFFFFFFFF)
            )[0]
        )

        raise ValueError(
            f"{root}: tower {tower_index}, coefficient {bad} "
            "does not fit in 32 bits"
        )

    return values.astype(np.uint32)


def pair_words(
    lane0: np.ndarray,
    lane1: np.ndarray,
) -> np.ndarray:
    if lane0.shape != lane1.shape:
        raise ValueError(
            "paired tower arrays have different shapes"
        )

    return (
        lane0.astype(np.uint64)
        | (
            lane1.astype(np.uint64)
            << np.uint64(32)
        )
    )


def split_words(
    paired: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    values = np.asarray(
        paired,
        dtype=np.uint64,
    )

    return (
        (
            values
            & np.uint64(0xFFFFFFFF)
        ).astype(np.uint32),
        np.right_shift(
            values,
            np.uint64(32),
        ).astype(np.uint32),
    )


def require_aligned_buffer(
    buffer,
    label: str,
    alignment: int = 8,
) -> None:
    address = int(
        getattr(
            buffer,
            "device_address",
            buffer.physical_address,
        )
    )

    if address % alignment != 0:
        raise RuntimeError(
            f"{label} device address 0x{address:x} "
            f"is not {alignment}-byte aligned"
        )

    if int(buffer.nbytes) % alignment != 0:
        raise RuntimeError(
            f"{label} length {buffer.nbytes} "
            f"is not a multiple of {alignment} bytes"
        )


def resolve_dma(overlay: Overlay):
    matches: list[str] = []

    for name, metadata in overlay.ip_dict.items():
        ip_type = str(
            metadata.get("type", "")
        ).lower()

        if (
            name.lower() == "dma"
            or "axi_dma" in ip_type
        ):
            matches.append(name)

    if len(matches) != 1:
        inventory = [
            (
                name,
                metadata.get("type", ""),
            )
            for name, metadata
            in overlay.ip_dict.items()
        ]

        raise RuntimeError(
            "Expected exactly one AXI DMA; "
            f"matches={matches}, inventory={inventory}"
        )

    return getattr(
        overlay,
        matches[0],
    )


def send_only(
    dma,
    buffer,
) -> float:
    buffer.flush()

    start_ns = time.perf_counter_ns()

    dma.sendchannel.transfer(buffer)
    dma.sendchannel.wait()

    return (
        time.perf_counter_ns()
        - start_ns
    ) / 1_000.0


def load_profile(
    vector_root: Path,
    tower_index: int,
) -> tuple[int, int]:
    metadata = read_json(
        vector_root
        / "profiles_q"
        / f"{tower_name(tower_index)}.json"
    )

    modulus = int(metadata["modulus"])
    mu = (1 << 60) // modulus

    if not (
        (1 << 29) < modulus < (1 << 30)
    ):
        raise ValueError(
            f"tower {tower_index}: modulus {modulus} "
            "is outside 2^29 < q < 2^30"
        )

    if mu >= (1 << 31):
        raise ValueError(
            f"tower {tower_index}: Barrett reciprocal "
            "does not fit in 31 bits"
        )

    return modulus, mu


def load_pair_data(
    vector_root: Path,
    tower0: int,
    tower1: int,
    digit_count: int,
) -> dict[str, object]:
    def paired(root: Path) -> np.ndarray:
        return pair_words(
            read_tower_u32(
                root,
                tower0,
            ),
            read_tower_u32(
                root,
                tower1,
            ),
        )

    inputs = {
        "a0": paired(
            vector_root / "input_a0_q_eval"
        ),
        "a1": paired(
            vector_root / "input_a1_q_eval"
        ),
        "b0": paired(
            vector_root / "input_b0_q_eval"
        ),
        "b1": paired(
            vector_root / "input_b1_q_eval"
        ),
    }

    digits: list[np.ndarray] = []
    key_b: list[np.ndarray] = []
    key_a: list[np.ndarray] = []

    for digit_index in range(digit_count):
        digit_dir = digit_name(digit_index)

        digits.append(
            paired(
                vector_root
                / "digits"
                / digit_dir
            )
        )

        key_b.append(
            paired(
                vector_root
                / "eval_key_b"
                / digit_dir
            )
        )

        key_a.append(
            paired(
                vector_root
                / "eval_key_a"
                / digit_dir
            )
        )

    expected = np.empty(
        (
            N,
            OUTPUT_WORDS_PER_CIPHERTEXT,
        ),
        dtype=np.uint64,
    )

    expected[:, 0] = paired(
        vector_root / "relinearized_c0_q"
    )

    expected[:, 1] = paired(
        vector_root / "relinearized_c1_q"
    )

    return {
        "inputs": inputs,
        "digits": digits,
        "key_b": key_b,
        "key_a": key_a,
        "expected": expected,
    }



def build_profile_table_frame(
    vector_root: Path,
    pair_count: int,
) -> np.ndarray:
    command_word = (
        np.uint64(PROFILE_TABLE_COMMAND)
        | (
            np.uint64(PROFILE_TABLE_COMMAND)
            << np.uint64(32)
        )
    )

    count_word = (
        np.uint64(pair_count)
        | (
            np.uint64(pair_count)
            << np.uint64(32)
        )
    )

    frame = np.empty(
        2 + 2 * pair_count,
        dtype=np.uint64,
    )

    frame[0] = command_word
    frame[1] = count_word

    offset = 2

    for pair_index in range(pair_count):
        tower0 = 2 * pair_index
        tower1 = tower0 + 1

        modulus0, mu0 = load_profile(
            vector_root,
            tower0,
        )

        modulus1, mu1 = load_profile(
            vector_root,
            tower1,
        )

        frame[offset] = (
            np.uint64(modulus0)
            | (
                np.uint64(modulus1)
                << np.uint64(32)
            )
        )

        frame[offset + 1] = (
            np.uint64(mu0)
            | (
                np.uint64(mu1)
                << np.uint64(32)
            )
        )

        offset += 2

    if offset != int(frame.size):
        raise RuntimeError(
            f"RLPT frame filled {offset} words; "
            f"expected {frame.size}"
        )

    return frame



def fill_multi_pair_frame_vectorized(
    destination,
    pair_data: dict[str, object],
    ciphertext_count: int,
    digit_count: int,
    pair_index: int,
    pair_count: int,
) -> None:
    command_word = (
        np.uint64(MULTI_PAIR_COMMAND)
        | (
            np.uint64(MULTI_PAIR_COMMAND)
            << np.uint64(32)
        )
    )

    count_word = (
        np.uint64(ciphertext_count)
        | (
            np.uint64(digit_count)
            << np.uint64(32)
        )
    )

    pair_word = (
        np.uint64(pair_index)
        | (
            np.uint64(pair_count)
            << np.uint64(32)
        )
    )

    destination[0] = command_word
    destination[1] = count_word
    destination[2] = pair_word

    words_per_coefficient = (
        EVAL_WORDS_PER_CIPHERTEXT
        * ciphertext_count
        + digit_count
        * (
            KEY_WORDS_PER_DIGIT
            + ciphertext_count
        )
    )

    payload = np.asarray(
        destination[3:],
        dtype=np.uint64,
    ).reshape(
        N,
        words_per_coefficient,
    )

    inputs = pair_data["inputs"]

    eval_words = (
        EVAL_WORDS_PER_CIPHERTEXT
        * ciphertext_count
    )

    eval_view = payload[
        :,
        :eval_words,
    ].reshape(
        N,
        ciphertext_count,
        EVAL_WORDS_PER_CIPHERTEXT,
    )

    eval_view[:, :, 0] = np.asarray(
        inputs["a0"],
        dtype=np.uint64,
    )[:, np.newaxis]

    eval_view[:, :, 1] = np.asarray(
        inputs["a1"],
        dtype=np.uint64,
    )[:, np.newaxis]

    eval_view[:, :, 2] = np.asarray(
        inputs["b0"],
        dtype=np.uint64,
    )[:, np.newaxis]

    eval_view[:, :, 3] = np.asarray(
        inputs["b1"],
        dtype=np.uint64,
    )[:, np.newaxis]

    digit_view = payload[
        :,
        eval_words:,
    ].reshape(
        N,
        digit_count,
        ciphertext_count
        + KEY_WORDS_PER_DIGIT,
    )

    key_b = np.stack(
        pair_data["key_b"],
        axis=1,
    ).astype(
        np.uint64,
        copy=False,
    )

    key_a = np.stack(
        pair_data["key_a"],
        axis=1,
    ).astype(
        np.uint64,
        copy=False,
    )

    digits = np.stack(
        pair_data["digits"],
        axis=1,
    ).astype(
        np.uint64,
        copy=False,
    )

    digit_view[:, :, 0] = key_b
    digit_view[:, :, 1] = key_a

    digit_view[
        :,
        :,
        KEY_WORDS_PER_DIGIT:,
    ] = digits[:, :, np.newaxis]


def build_normal_pair_frames(
    pair_data: list[dict[str, object]],
    send_words_per_pair: int,
    ciphertext_count: int,
    digit_count: int,
) -> tuple[list[np.ndarray], float]:
    pair_count = len(pair_data)

    start_ns = time.perf_counter_ns()

    frames: list[np.ndarray] = []

    for pair_index, data in enumerate(pair_data):
        frame = np.empty(
            send_words_per_pair,
            dtype=np.uint64,
        )

        fill_multi_pair_frame_vectorized(
            frame,
            data,
            ciphertext_count,
            digit_count,
            pair_index,
            pair_count,
        )

        frames.append(frame)

    elapsed_us = (
        time.perf_counter_ns()
        - start_ns
    ) / 1_000.0

    return frames, elapsed_us



def allocate_prefilled_cma_arena(
    pair_data: list[dict[str, object]],
    send_words_per_pair: int,
    ciphertext_count: int,
    digit_count: int,
) -> tuple[object, float]:
    pair_count = len(pair_data)

    start_ns = time.perf_counter_ns()

    arena = allocate(
        shape=(
            pair_count,
            send_words_per_pair,
        ),
        dtype=np.uint64,
    )

    try:
        require_aligned_buffer(
            arena,
            "packed RLMP CMA send arena",
        )

        for pair_index, data in enumerate(pair_data):
            fill_multi_pair_frame_vectorized(
                arena[pair_index],
                data,
                ciphertext_count,
                digit_count,
                pair_index,
                pair_count,
            )

        arena.flush()
    except Exception:
        arena.freebuffer()
        raise

    elapsed_us = (
        time.perf_counter_ns()
        - start_ns
    ) / 1_000.0

    return arena, elapsed_us

def allocate_prefilled_cma_frames(
    pair_data: list[dict[str, object]],
    send_words_per_pair: int,
    ciphertext_count: int,
    digit_count: int,
) -> tuple[list[object], float]:
    pair_count = len(pair_data)

    buffers: list[object] = []

    start_ns = time.perf_counter_ns()

    try:
        for pair_index, data in enumerate(pair_data):
            buffer = allocate(
                shape=(send_words_per_pair,),
                dtype=np.uint64,
            )

            buffers.append(buffer)

            require_aligned_buffer(
                buffer,
                f"RLMP CMA send buffer {pair_index}",
            )

            fill_multi_pair_frame_vectorized(
                buffer,
                data,
                ciphertext_count,
                digit_count,
                pair_index,
                pair_count,
            )

            buffer.flush()
    except Exception:
        for buffer in buffers:
            buffer.freebuffer()

        raise

    elapsed_us = (
        time.perf_counter_ns()
        - start_ns
    ) / 1_000.0

    return buffers, elapsed_us

def validate_session(
    receive_buffer,
    pair_data: list[dict[str, object]],
    ciphertext_count: int,
) -> None:
    pair_count = len(pair_data)

    actual = np.asarray(
        receive_buffer,
        dtype=np.uint64,
    ).reshape(
        pair_count,
        N,
        ciphertext_count,
        OUTPUT_WORDS_PER_CIPHERTEXT,
    )

    for pair_index, data in enumerate(pair_data):
        expected = np.asarray(
            data["expected"],
            dtype=np.uint64,
        )[
            :,
            np.newaxis,
            :,
        ]

        mismatches = (
            actual[pair_index]
            != expected
        )

        if not np.any(mismatches):
            continue

        coefficient, ciphertext, component = np.argwhere(
            mismatches
        )[0]

        raise AssertionError(
            f"pair {pair_index} mismatch at "
            f"coefficient {int(coefficient)}, "
            f"ciphertext {int(ciphertext)}, "
            f"component c{int(component)}: "
            f"result="
            f"{int(actual[pair_index, coefficient, ciphertext, component])}, "
            f"expected={int(expected[coefficient, 0, component])}"
        )


def write_first_ciphertext_session_results(
    receive_buffer,
    result_root: Path,
    pair_count: int,
    ciphertext_count: int,
) -> None:
    actual = np.asarray(
        receive_buffer,
        dtype=np.uint64,
    ).reshape(
        pair_count,
        N,
        ciphertext_count,
        OUTPUT_WORDS_PER_CIPHERTEXT,
    )

    for pair_index in range(pair_count):
        first = actual[
            pair_index,
            :,
            0,
            :,
        ]

        tower0 = 2 * pair_index
        tower1 = tower0 + 1

        for component in range(
            OUTPUT_WORDS_PER_CIPHERTEXT
        ):
            lane0, lane1 = split_words(
                first[:, component]
            )

            component_root = (
                result_root
                / f"c{component}"
            )

            component_root.mkdir(
                parents=True,
                exist_ok=True,
            )

            lane0.astype("<u4").tofile(
                component_root
                / f"{tower_name(tower0)}.bin"
            )

            lane1.astype("<u4").tofile(
                component_root
                / f"{tower_name(tower1)}.bin"
            )




def run_multi_pair_session(
    dma,
    send_mode: str,
    send_arena,
    send_buffers: list[object],
    normal_frames: list[np.ndarray] | None,
    receive_buffer,
    total_receive_words: int,
    send_bytes_per_pair: int,
    ciphertext_count: int,
    pair_data: list[dict[str, object]],
    result_root: Path | None,
) -> tuple[float, float, float, float]:
    pair_count = len(pair_data)

    if send_mode == "arena-cma":
        if send_arena is None:
            raise ValueError(
                "arena-cma mode requires a packed CMA send arena"
            )

        if send_buffers or normal_frames is not None:
            raise ValueError(
                "arena-cma mode received incompatible send storage"
            )

    elif send_mode == "all-cma":
        if len(send_buffers) != pair_count:
            raise ValueError(
                "all-cma mode requires one send buffer per pair"
            )

        if send_arena is not None or normal_frames is not None:
            raise ValueError(
                "all-cma mode received incompatible send storage"
            )

    elif send_mode == "reuse-copy":
        if len(send_buffers) != 1:
            raise ValueError(
                "reuse-copy mode requires exactly one CMA send buffer"
            )

        if send_arena is not None:
            raise ValueError(
                "reuse-copy mode cannot use a CMA send arena"
            )

        if normal_frames is None:
            raise ValueError(
                "reuse-copy mode requires prepacked normal frames"
            )

        if len(normal_frames) != pair_count:
            raise ValueError(
                "reuse-copy mode requires one normal frame per pair"
            )

    else:
        raise ValueError(
            f"unsupported send mode: {send_mode}"
        )

    receive_view = receive_buffer[
        :total_receive_words
    ]

    receive_view[:] = 0
    receive_buffer.flush()

    session_start_ns = time.perf_counter_ns()

    dma_call_us = 0.0
    copy_flush_us = 0.0

    recv_setup_start_ns = time.perf_counter_ns()

    dma.recvchannel.transfer(
        receive_buffer,
        start=0,
        nbytes=receive_view.nbytes,
    )

    dma_call_us += (
        time.perf_counter_ns()
        - recv_setup_start_ns
    ) / 1_000.0

    for pair_index in range(pair_count):
        if send_mode == "arena-cma":
            send_view = send_arena[
                pair_index
            ]

            if send_view.nbytes != send_bytes_per_pair:
                raise RuntimeError(
                    f"CMA arena row has {send_view.nbytes} bytes; "
                    f"expected {send_bytes_per_pair}"
                )

            send_start_ns = time.perf_counter_ns()

            dma.sendchannel.transfer(
                send_view
            )

        elif send_mode == "all-cma":
            send_start_ns = time.perf_counter_ns()

            dma.sendchannel.transfer(
                send_buffers[pair_index]
            )

        else:
            send_buffer = send_buffers[0]

            copy_start_ns = time.perf_counter_ns()

            np.copyto(
                send_buffer,
                normal_frames[pair_index],
                casting="no",
            )

            send_buffer.flush()

            copy_flush_us += (
                time.perf_counter_ns()
                - copy_start_ns
            ) / 1_000.0

            send_start_ns = time.perf_counter_ns()

            dma.sendchannel.transfer(
                send_buffer
            )

        dma.sendchannel.wait()

        dma_call_us += (
            time.perf_counter_ns()
            - send_start_ns
        ) / 1_000.0

    receive_tail_start_ns = time.perf_counter_ns()

    dma.recvchannel.wait()

    dma_call_us += (
        time.perf_counter_ns()
        - receive_tail_start_ns
    ) / 1_000.0

    session_wall_us = (
        time.perf_counter_ns()
        - session_start_ns
    ) / 1_000.0

    receive_buffer.invalidate()

    validate_session(
        receive_view,
        pair_data,
        ciphertext_count,
    )

    if result_root is not None:
        write_first_ciphertext_session_results(
            receive_view,
            result_root,
            pair_count,
            ciphertext_count,
        )

    dispatch_gap_us = (
        session_wall_us
        - dma_call_us
        - copy_flush_us
    )

    return (
        dma_call_us,
        session_wall_us,
        copy_flush_us,
        dispatch_gap_us,
    )

def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Run the exact persistent-output six-pair coefficient-major "
            "OpenFHE BV relinearization session on PYNQ-Z2."
        )
    )

    parser.add_argument(
        "--overlay",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--vectors",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--results",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--timed-runs",
        type=int,
        default=5,
    )

    parser.add_argument(
        "--ciphertexts",
        type=int,
        default=8,
    )

    parser.add_argument(
        "--send-buffer-mode",
        choices=(
            "auto",
            "arena-cma",
            "all-cma",
            "reuse-copy",
        ),
        default="auto",
        help=(
            "arena-cma packs every pair into one contiguous CMA arena and "
            "uses DMA start offsets; all-cma uses one CMA buffer per pair; "
            "reuse-copy uses one CMA buffer and prepacked normal frames; "
            "auto tries arena-cma, then all-cma, then reuse-copy"
        ),
    )

    args = parser.parse_args()

    if args.timed_runs < 1:
        parser.error(
            "--timed-runs must be positive"
        )

    if not 8 <= args.ciphertexts <= MAX_BATCH:
        parser.error(
            f"--ciphertexts must be between 8 and {MAX_BATCH}"
        )

    vector_root = args.vectors.resolve()
    result_root = args.results.resolve()

    metadata = read_json(
        vector_root / "metadata.json"
    )

    if metadata.get("technique") != "BV":
        raise ValueError(
            "board checkpoint requires BV vectors"
        )

    ring_dimension = int(
        metadata["ring_dimension"]
    )

    tower_count = int(
        metadata["q_towers"]
    )

    p_towers = int(
        metadata["p_towers"]
    )

    digit_count = int(
        metadata["digits"]
    )

    digit_towers = int(
        metadata["digit_towers"]
    )

    eval_key_parts = int(
        metadata["eval_key_parts"]
    )

    eval_key_towers = int(
        metadata["eval_key_towers"]
    )

    max_q_bits = int(
        metadata["max_q_modulus_bits"]
    )

    if ring_dimension != N:
        raise ValueError(
            f"overlay requires N={N}"
        )

    if tower_count != 12:
        raise ValueError(
            f"board checkpoint expects 12 Q towers; "
            f"got {tower_count}"
        )

    if tower_count % 2:
        raise ValueError(
            "Q tower count must be even"
        )

    if p_towers != 0:
        raise ValueError(
            "BV vectors unexpectedly contain P towers"
        )

    if not (
        digit_count == DIGIT_COUNT_EXPECTED
        and digit_count == eval_key_parts
        and digit_towers == tower_count
        and eval_key_towers == tower_count
    ):
        raise ValueError(
            "BV digit/evaluation-key dimensions are inconsistent"
        )

    if max_q_bits > 30:
        raise ValueError(
            "current FPGA Barrett datapath supports "
            "at most 30-bit Q moduli"
        )

    pair_count = tower_count // 2

    if pair_count != PAIR_COUNT_EXPECTED:
        raise ValueError(
            f"expected {PAIR_COUNT_EXPECTED} tower pairs"
        )

    words_per_coefficient = (
        EVAL_WORDS_PER_CIPHERTEXT
        * args.ciphertexts
        + digit_count
        * (
            KEY_WORDS_PER_DIGIT
            + DIGIT_WORDS_PER_CIPHERTEXT
            * args.ciphertexts
        )
    )

    legacy_words_per_coefficient = (
        args.ciphertexts
        * (
            EVAL_WORDS_PER_CIPHERTEXT
            + 3 * digit_count
        )
    )

    profile_words = (
        2
        + 2 * pair_count
    )

    send_words_per_pair = (
        3
        + N
        * words_per_coefficient
    )

    receive_words_per_pair = (
        N
        * args.ciphertexts
        * OUTPUT_WORDS_PER_CIPHERTEXT
    )

    total_receive_words = (
        pair_count
        * receive_words_per_pair
    )

    profile_bytes = (
        profile_words
        * np.dtype(np.uint64).itemsize
    )

    send_bytes_per_pair = (
        send_words_per_pair
        * np.dtype(np.uint64).itemsize
    )

    total_receive_bytes = (
        total_receive_words
        * np.dtype(np.uint64).itemsize
    )

    if profile_bytes > MAX_DMA_BYTES:
        raise ValueError(
            "RLPT profile table exceeds the DMA length limit"
        )

    if send_bytes_per_pair > MAX_DMA_BYTES:
        raise ValueError(
            f"RLMP pair frame is {send_bytes_per_pair} bytes, "
            f"exceeding the {DMA_LENGTH_WIDTH}-bit DMA limit"
        )

    if total_receive_bytes > MAX_DMA_BYTES:
        raise ValueError(
            f"persistent output frame is {total_receive_bytes} bytes, "
            f"exceeding the {DMA_LENGTH_WIDTH}-bit DMA limit"
        )

    result_root.mkdir(
        parents=True,
        exist_ok=True,
    )

    print(
        "Preparing exact paired-tower source vectors for "
        "persistent-output multi-pair session..."
    )

    pair_data: list[dict[str, object]] = []

    for pair_index in range(pair_count):
        tower0 = 2 * pair_index
        tower1 = tower0 + 1

        pair_data.append(
            load_pair_data(
                vector_root,
                tower0,
                tower1,
                digit_count,
            )
        )

        print(
            f"  pair={pair_index} towers={tower0},{tower1}"
        )

    profile_table_frame = build_profile_table_frame(
        vector_root,
        pair_count,
    )

    overlay_path = args.overlay.resolve()

    if overlay_path.with_suffix(".xsa").exists():
        raise RuntimeError(
            "Rename the same-stem XSA before loading the PYNQ overlay"
        )

    overlay = Overlay(
        str(overlay_path),
        download=True,
    )

    dma = resolve_dma(overlay)

    profile_buffer = allocate(
        shape=(profile_words,),
        dtype=np.uint64,
    )

    try:
        require_aligned_buffer(
            profile_buffer,
            "RLPT profile-table buffer",
        )

        profile_buffer[:] = profile_table_frame

        profile_setup_us = send_only(
            dma,
            profile_buffer,
        )

        send_arena = None
        send_buffers: list[object] = []
        normal_frames: list[np.ndarray] | None = None
        receive_buffer = None

        selected_send_buffer_mode = (
            args.send_buffer_mode
        )

        prepack_us = 0.0
        allocation_fallback_reasons: list[str] = []

        try:
            if selected_send_buffer_mode in (
                "auto",
                "arena-cma",
            ):
                try:
                    (
                        send_arena,
                        prepack_us,
                    ) = allocate_prefilled_cma_arena(
                        pair_data,
                        send_words_per_pair,
                        args.ciphertexts,
                        digit_count,
                    )

                    receive_buffer = allocate(
                        shape=(total_receive_words,),
                        dtype=np.uint64,
                    )

                    require_aligned_buffer(
                        receive_buffer,
                        "persistent S2MM receive buffer",
                    )

                    selected_send_buffer_mode = (
                        "arena-cma"
                    )
                except Exception as error:
                    if receive_buffer is not None:
                        receive_buffer.freebuffer()
                        receive_buffer = None

                    if send_arena is not None:
                        send_arena.freebuffer()
                        send_arena = None

                    if args.send_buffer_mode == "arena-cma":
                        raise

                    allocation_fallback_reasons.append(
                        "arena-cma="
                        f"{type(error).__name__}: {error}"
                    )

                    selected_send_buffer_mode = (
                        "auto"
                    )

            if selected_send_buffer_mode in (
                "auto",
                "all-cma",
            ):
                try:
                    (
                        send_buffers,
                        prepack_us,
                    ) = allocate_prefilled_cma_frames(
                        pair_data,
                        send_words_per_pair,
                        args.ciphertexts,
                        digit_count,
                    )

                    receive_buffer = allocate(
                        shape=(total_receive_words,),
                        dtype=np.uint64,
                    )

                    require_aligned_buffer(
                        receive_buffer,
                        "persistent S2MM receive buffer",
                    )

                    selected_send_buffer_mode = (
                        "all-cma"
                    )
                except Exception as error:
                    if receive_buffer is not None:
                        receive_buffer.freebuffer()
                        receive_buffer = None

                    for send_buffer in send_buffers:
                        send_buffer.freebuffer()

                    send_buffers = []

                    if args.send_buffer_mode == "all-cma":
                        raise

                    allocation_fallback_reasons.append(
                        "all-cma="
                        f"{type(error).__name__}: {error}"
                    )

                    selected_send_buffer_mode = (
                        "reuse-copy"
                    )

            if selected_send_buffer_mode == "reuse-copy":
                (
                    normal_frames,
                    prepack_us,
                ) = build_normal_pair_frames(
                    pair_data,
                    send_words_per_pair,
                    args.ciphertexts,
                    digit_count,
                )

                reusable_send_buffer = allocate(
                    shape=(send_words_per_pair,),
                    dtype=np.uint64,
                )

                require_aligned_buffer(
                    reusable_send_buffer,
                    "reusable RLMP CMA send buffer",
                )

                send_buffers = [
                    reusable_send_buffer
                ]

                receive_buffer = allocate(
                    shape=(total_receive_words,),
                    dtype=np.uint64,
                )

                require_aligned_buffer(
                    receive_buffer,
                    "persistent S2MM receive buffer",
                )

            if receive_buffer is None:
                raise RuntimeError(
                    "no persistent S2MM receive buffer was allocated"
                )

            (
                warmup_dma_call_us,
                warmup_session_wall_us,
                warmup_copy_flush_us,
                warmup_dispatch_gap_us,
            ) = run_multi_pair_session(
                dma,
                selected_send_buffer_mode,
                send_arena,
                send_buffers,
                normal_frames,
                receive_buffer,
                total_receive_words,
                send_bytes_per_pair,
                args.ciphertexts,
                pair_data,
                result_root,
            )

            dma_call_timings: list[float] = []
            wall_timings: list[float] = []
            copy_timings: list[float] = []
            dispatch_gap_timings: list[float] = []

            for run_index in range(
                args.timed_runs
            ):
                (
                    dma_call_us,
                    session_wall_us,
                    copy_flush_us,
                    dispatch_gap_us,
                ) = run_multi_pair_session(
                    dma,
                    selected_send_buffer_mode,
                    send_arena,
                    send_buffers,
                    normal_frames,
                    receive_buffer,
                    total_receive_words,
                    send_bytes_per_pair,
                    args.ciphertexts,
                    pair_data,
                    None,
                )

                dma_call_timings.append(
                    dma_call_us
                )

                wall_timings.append(
                    session_wall_us
                )

                copy_timings.append(
                    copy_flush_us
                )

                dispatch_gap_timings.append(
                    dispatch_gap_us
                )

                print(
                    f"run={run_index} exact "
                    f"dma_call_us={dma_call_us:.2f} "
                    f"session_wall_us={session_wall_us:.2f} "
                    f"copy_flush_us={copy_flush_us:.2f} "
                    f"dispatch_gap_us={dispatch_gap_us:.2f}"
                )

            median_dma_call_us = statistics.median(
                dma_call_timings
            )

            median_session_wall_us = statistics.median(
                wall_timings
            )

            median_copy_flush_us = statistics.median(
                copy_timings
            )

            median_dispatch_gap_us = statistics.median(
                dispatch_gap_timings
            )
        finally:
            if receive_buffer is not None:
                receive_buffer.freebuffer()

            for send_buffer in send_buffers:
                send_buffer.freebuffer()

            if send_arena is not None:
                send_arena.freebuffer()
    finally:
        profile_buffer.freebuffer()

    payload_input_ideal_us = (
        pair_count
        * N
        * words_per_coefficient
        / CLOCK_HZ
        * 1_000_000.0
    )

    external_input_ideal_us = (
        pair_count
        * send_words_per_pair
        / CLOCK_HZ
        * 1_000_000.0
    )

    input_bound_rate = (
        args.ciphertexts
        * 1_000_000.0
        / external_input_ideal_us
    )

    input_stream_efficiency = (
        external_input_ideal_us
        / median_session_wall_us
    )

    overhead_above_input_floor_us = (
        median_session_wall_us
        - external_input_ideal_us
    )

    dma_call_us_per_ciphertext = (
        median_dma_call_us
        / args.ciphertexts
    )

    session_wall_us_per_ciphertext = (
        median_session_wall_us
        / args.ciphertexts
    )

    dma_call_rate = (
        1_000_000.0
        / dma_call_us_per_ciphertext
    )

    session_wall_rate = (
        1_000_000.0
        / session_wall_us_per_ciphertext
    )

    verified_tower_components = (
        tower_count
        * args.ciphertexts
        * OUTPUT_WORDS_PER_CIPHERTEXT
    )

    verified_residue_words = (
        tower_count
        * N
        * args.ciphertexts
        * OUTPUT_WORDS_PER_CIPHERTEXT
    )

    input_reduction = (
        1.0
        - words_per_coefficient
        / legacy_words_per_coefficient
    )

    print()
    print(
        "PASS: every persistent-output RLMP session result "
        "matches OpenFHE"
    )

    print(f"towers={tower_count}")
    print(f"pairs={pair_count}")
    print(f"digits={digit_count}")
    print(f"ciphertexts={args.ciphertexts}")
    print(
        f"words_per_coefficient={words_per_coefficient}"
    )
    print(
        "legacy_words_per_coefficient="
        f"{legacy_words_per_coefficient}"
    )
    print(
        f"input_reduction={input_reduction:.4%}"
    )
    print(f"profile_table_words={profile_words}")
    print(f"profile_table_bytes={profile_bytes}")
    print(
        f"send_bytes_per_pair={send_bytes_per_pair}"
    )
    print(
        f"total_input_bytes_per_session="
        f"{pair_count * send_bytes_per_pair}"
    )
    print(
        f"total_output_bytes_per_session="
        f"{total_receive_bytes}"
    )
    print(
        "send_dma_transactions_per_session="
        f"{pair_count}"
    )
    print(
        "receive_dma_transactions_per_session=1"
    )
    print(
        f"profile_setup_us={profile_setup_us:.2f}"
    )
    print(
        f"send_buffer_mode={selected_send_buffer_mode}"
    )
    print(
        f"prepack_us={prepack_us:.2f}"
    )

    if allocation_fallback_reasons:
        print(
            "allocation_fallback_reasons="
            + " | ".join(
                allocation_fallback_reasons
            )
        )
    print(
        f"warmup_dma_call_us={warmup_dma_call_us:.2f}"
    )
    print(
        f"warmup_session_wall_us={warmup_session_wall_us:.2f}"
    )
    print(
        f"warmup_copy_flush_us={warmup_copy_flush_us:.2f}"
    )
    print(
        f"warmup_dispatch_gap_us={warmup_dispatch_gap_us:.2f}"
    )
    print(
        f"median_dma_call_us={median_dma_call_us:.2f}"
    )
    print(
        f"median_session_wall_us={median_session_wall_us:.2f}"
    )
    print(
        f"median_copy_flush_us={median_copy_flush_us:.2f}"
    )
    print(
        f"median_dispatch_gap_us={median_dispatch_gap_us:.2f}"
    )
    print(
        f"payload_input_ideal_us={payload_input_ideal_us:.2f}"
    )
    print(
        f"external_input_ideal_us={external_input_ideal_us:.2f}"
    )
    print(
        "input_bound_relinearized_EvalMult_per_second="
        f"{input_bound_rate:.2f}"
    )
    print(
        "input_stream_efficiency="
        f"{input_stream_efficiency:.4%}"
    )
    print(
        "overhead_above_input_floor_us="
        f"{overhead_above_input_floor_us:.2f}"
    )
    print(
        f"verified_tower_components="
        f"{verified_tower_components}"
    )
    print(
        f"verified_residue_words="
        f"{verified_residue_words}"
    )
    print(
        "dma_call_us_per_relinearized_EvalMult="
        f"{dma_call_us_per_ciphertext:.2f}"
    )
    print(
        "dma_call_relinearized_EvalMult_per_second="
        f"{dma_call_rate:.2f}"
    )
    print(
        "session_wall_us_per_relinearized_EvalMult="
        f"{session_wall_us_per_ciphertext:.2f}"
    )
    print(
        "session_wall_relinearized_EvalMult_per_second="
        f"{session_wall_rate:.2f}"
    )
    print(f"results={result_root}")


if __name__ == "__main__":
    main()
