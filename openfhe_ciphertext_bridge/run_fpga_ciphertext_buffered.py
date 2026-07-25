#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import statistics
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from pynq import Overlay, allocate


N = 4096
TWIDDLES = N - 1

PROFILE_COMMAND = np.uint32(0x50524F46)
BATCH_COMMAND = np.uint32(0x4D554C42)

PROFILE_WORDS = 16_385
BUFFERED_STEADY_CYCLES_PER_PRODUCT = 23_993
CLOCK_HZ = 100_000_000


@dataclass(frozen=True)
class ProfileKey:
    modulus0: int
    psi0: int
    modulus1: int
    psi1: int
    cyclotomic_order: int


class ProfileFrameCache:
    def __init__(self) -> None:
        self._frames: dict[ProfileKey, np.ndarray] = {}

    def get(
        self,
        profile0: Path,
        profile1: Path,
    ) -> tuple[ProfileKey, np.ndarray]:
        metadata0 = read_json(profile0 / "profile.json")
        metadata1 = read_json(profile1 / "profile.json")

        key = ProfileKey(
            modulus0=int(metadata0["modulus"]),
            psi0=int(metadata0["psi"]),
            modulus1=int(metadata1["modulus"]),
            psi1=int(metadata1["psi"]),
            cyclotomic_order=int(metadata0["cyclotomic_order"]),
        )

        if int(metadata1["cyclotomic_order"]) != key.cyclotomic_order:
            raise ValueError("Paired profiles use different cyclotomic orders")

        frame = self._frames.get(key)

        if frame is None:
            frame = build_profile_frame(profile0, profile1)
            self._frames[key] = frame

        return key, frame


def read_json(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def tower_name(index: int) -> str:
    return f"tower{index:03d}"


def read_mem(path: Path, expected_words: int) -> np.ndarray:
    values = [
        int(line.strip(), 16)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]

    if len(values) != expected_words:
        raise ValueError(
            f"{path}: found {len(values)} words; expected {expected_words}"
        )

    return np.asarray(values, dtype=np.uint32)


def read_u32le(path: Path, expected_words: int) -> np.ndarray:
    values = np.fromfile(path, dtype="<u4")

    if values.size != expected_words:
        raise ValueError(
            f"{path}: found {values.size} words; expected {expected_words}"
        )

    return np.asarray(values, dtype=np.uint32)


def write_u32le(path: Path, words: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    np.asarray(words, dtype="<u4").tofile(path)


def pair_words(lane0: np.ndarray, lane1: np.ndarray) -> np.ndarray:
    if lane0.shape != lane1.shape:
        raise ValueError("Lane arrays have different shapes")

    return (
        lane0.astype(np.uint64)
        | (lane1.astype(np.uint64) << np.uint64(32))
    )


def split_results(paired: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    values = np.asarray(paired, dtype=np.uint64)

    lane0 = (
        values & np.uint64(0xFFFFFFFF)
    ).astype(np.uint32)

    lane1 = np.right_shift(
        values,
        np.uint64(32),
    ).astype(np.uint32)

    return lane0, lane1


def build_profile_lane(
    profile_directory: Path,
) -> tuple[np.uint32, np.uint32, np.ndarray]:
    metadata = read_json(profile_directory / "profile.json")
    modulus = int(metadata["modulus"])
    reciprocal = (1 << 60) // modulus

    if modulus >= 1 << 30:
        raise ValueError(
            f"{profile_directory}: modulus is not below 2^30"
        )

    if reciprocal >= 1 << 31:
        raise ValueError(
            f"{profile_directory}: reciprocal {reciprocal} "
            "does not fit 31 bits"
        )

    payload = np.concatenate(
        [
            read_mem(
                profile_directory / "twist_factors.mem",
                N,
            ),
            read_mem(
                profile_directory / "forward_twiddles.mem",
                TWIDDLES,
            ),
            read_mem(
                profile_directory / "inverse_twiddles.mem",
                TWIDDLES,
            ),
            read_mem(
                profile_directory / "inverse_scale_factors.mem",
                N,
            ),
        ]
    ).astype(np.uint32, copy=False)

    if payload.size != 16_382:
        raise RuntimeError(
            f"Profile payload contains {payload.size} words; "
            "expected 16382"
        )

    return (
        np.uint32(modulus),
        np.uint32(reciprocal),
        payload,
    )


def build_profile_frame(
    profile0: Path,
    profile1: Path,
) -> np.ndarray:
    modulus0, reciprocal0, payload0 = build_profile_lane(profile0)
    modulus1, reciprocal1, payload1 = build_profile_lane(profile1)

    lane0 = np.empty(PROFILE_WORDS, dtype=np.uint32)
    lane1 = np.empty(PROFILE_WORDS, dtype=np.uint32)

    lane0[0] = PROFILE_COMMAND
    lane1[0] = PROFILE_COMMAND
    lane0[1] = modulus0
    lane1[1] = modulus1
    lane0[2] = reciprocal0
    lane1[2] = reciprocal1
    lane0[3:] = payload0
    lane1[3:] = payload1

    return pair_words(lane0, lane1)


def build_batch_frame(
    dma0: np.ndarray,
    dma1: np.ndarray,
    raw_product_count: int,
) -> np.ndarray:
    expected_dma_words = raw_product_count * 2 * N

    if (
        dma0.size != expected_dma_words
        or dma1.size != expected_dma_words
    ):
        raise ValueError(
            "DMA tower input length does not match "
            "raw_product_count * 8192"
        )

    words = 2 + expected_dma_words
    lane0 = np.empty(words, dtype=np.uint32)
    lane1 = np.empty(words, dtype=np.uint32)

    lane0[0] = BATCH_COMMAND
    lane1[0] = BATCH_COMMAND
    lane0[1] = np.uint32(raw_product_count)
    lane1[1] = np.uint32(raw_product_count)
    lane0[2:] = dma0
    lane1[2:] = dma1

    return pair_words(lane0, lane1)


def resolve_dma(overlay: Overlay):
    matches: list[str] = []

    for name, metadata in overlay.ip_dict.items():
        ip_type = str(metadata.get("type", "")).lower()

        if name.lower() == "dma" or "axi_dma" in ip_type:
            matches.append(name)

    if len(matches) != 1:
        inventory = [
            (name, metadata.get("type", ""))
            for name, metadata in overlay.ip_dict.items()
        ]

        raise RuntimeError(
            "Expected exactly one AXI DMA; "
            f"matches={matches}, inventory={inventory}"
        )

    return getattr(overlay, matches[0])


def send_only(dma, buffer) -> float:
    buffer.flush()

    start_ns = time.perf_counter_ns()

    dma.sendchannel.transfer(buffer)
    dma.sendchannel.wait()

    return (
        time.perf_counter_ns() - start_ns
    ) / 1_000.0


def run_frame(
    dma,
    send_buffer,
    receive_buffer,
) -> float:
    receive_buffer[:] = 0
    send_buffer.flush()
    receive_buffer.flush()

    start_ns = time.perf_counter_ns()

    dma.recvchannel.transfer(receive_buffer)
    dma.sendchannel.transfer(send_buffer)
    dma.sendchannel.wait()
    dma.recvchannel.wait()

    elapsed_us = (
        time.perf_counter_ns() - start_ns
    ) / 1_000.0

    receive_buffer.invalidate()

    return elapsed_us


def require_equal(
    actual: np.ndarray,
    expected: np.ndarray,
    label: str,
) -> None:
    if np.array_equal(actual, expected):
        return

    mismatch = int(np.flatnonzero(actual != expected)[0])
    raw_product = mismatch // N
    coefficient = mismatch % N

    raise AssertionError(
        f"{label} mismatch at raw product {raw_product}, "
        f"coefficient {coefficient}: "
        f"result={int(actual[mismatch])}, "
        f"expected={int(expected[mismatch])}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Run OpenFHE BGVRNS ciphertext component multiplication "
            "through the timing-closed four-wide buffered PYNQ-Z2 overlay."
        )
    )

    parser.add_argument("--overlay", type=Path, required=True)
    parser.add_argument("--vectors", type=Path, required=True)
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--timed-runs", type=int, default=3)

    args = parser.parse_args()

    if args.timed_runs < 1:
        parser.error("--timed-runs must be positive")

    vector_root = args.vectors.resolve()
    result_root = args.results.resolve()
    metadata = read_json(vector_root / "metadata.json")

    tower_count = int(metadata["tower_count"])
    ciphertext_count = int(metadata["ciphertext_count"])
    raw_products_per_ciphertext = int(
        metadata["raw_products_per_ciphertext"]
    )
    raw_product_count = int(metadata["raw_product_count"])
    ring_dimension = int(metadata["ring_dimension"])

    if tower_count < 1 or ciphertext_count < 1:
        raise ValueError(
            "tower_count and ciphertext_count must be positive"
        )

    if raw_products_per_ciphertext != 4:
        raise ValueError(
            "This executor requires four raw products per ciphertext"
        )

    if raw_product_count != ciphertext_count * 4:
        raise ValueError(
            "raw_product_count does not equal ciphertext_count * 4"
        )

    if ring_dimension != N:
        raise ValueError(
            f"This overlay requires N={N}; metadata uses {ring_dimension}"
        )

    pair_count = (tower_count + 1) // 2
    expected_tower_words = raw_product_count * N
    expected_dma_words = raw_product_count * 2 * N

    result_root.mkdir(parents=True, exist_ok=True)

    overlay_path = args.overlay.resolve()
    xsa_path = overlay_path.with_suffix(".xsa")

    if xsa_path.exists():
        raise RuntimeError(
            f"Rename or remove {xsa_path}; "
            "PYNQ may select it instead of the HWH"
        )

    overlay = Overlay(
        str(overlay_path),
        download=True,
    )

    dma = resolve_dma(overlay)
    frame_cache = ProfileFrameCache()
    loaded_key: ProfileKey | None = None

    profile_load_us_total = 0.0
    pair_median_us_total = 0.0
    tower_products_verified = 0

    print(
        "Ciphertext batch: "
        f"towers={tower_count}, "
        f"pairs={pair_count}, "
        f"ciphertexts={ciphertext_count}, "
        f"raw-products={raw_product_count}"
    )

    print(
        "pair  towers       profile_us  median_us  "
        "us/ciphertext  raw-products/s"
    )

    for pair_index in range(pair_count):
        tower0 = 2 * pair_index
        tower1_real = tower0 + 1 < tower_count
        tower1 = tower0 + 1 if tower1_real else tower0

        name0 = tower_name(tower0)
        name1 = tower_name(tower1)

        profile0 = vector_root / "profiles" / name0
        profile1 = vector_root / "profiles" / name1

        key, profile_frame = frame_cache.get(
            profile0,
            profile1,
        )

        dma0 = read_u32le(
            vector_root / "towers" / name0 / "dma_input.bin",
            expected_dma_words,
        )

        dma1 = read_u32le(
            vector_root / "towers" / name1 / "dma_input.bin",
            expected_dma_words,
        )

        expected0 = read_u32le(
            vector_root
            / "towers"
            / name0
            / "openfhe_expected.bin",
            expected_tower_words,
        )

        expected1 = read_u32le(
            vector_root
            / "towers"
            / name1
            / "openfhe_expected.bin",
            expected_tower_words,
        )

        profile_us = 0.0

        if loaded_key != key:
            profile_buffer = allocate(
                shape=profile_frame.shape,
                dtype=np.uint64,
            )

            try:
                profile_buffer[:] = profile_frame
                profile_us = send_only(dma, profile_buffer)
                time.sleep(0.001)
            finally:
                profile_buffer.freebuffer()

            loaded_key = key

        frame = build_batch_frame(
            dma0,
            dma1,
            raw_product_count,
        )

        send_buffer = allocate(
            shape=frame.shape,
            dtype=np.uint64,
        )

        receive_buffer = allocate(
            shape=(expected_tower_words,),
            dtype=np.uint64,
        )

        try:
            send_buffer[:] = frame

            warmup_us = run_frame(
                dma,
                send_buffer,
                receive_buffer,
            )

            warmup0, warmup1 = split_results(
                receive_buffer
            )

            require_equal(
                warmup0,
                expected0,
                f"pair {pair_index} warmup lane0",
            )

            require_equal(
                warmup1,
                expected1,
                f"pair {pair_index} warmup lane1",
            )

            timings_us: list[float] = []
            actual0 = warmup0
            actual1 = warmup1

            for run_index in range(args.timed_runs):
                elapsed_us = run_frame(
                    dma,
                    send_buffer,
                    receive_buffer,
                )

                actual0, actual1 = split_results(
                    receive_buffer
                )

                require_equal(
                    actual0,
                    expected0,
                    f"pair {pair_index} run {run_index} lane0",
                )

                require_equal(
                    actual1,
                    expected1,
                    f"pair {pair_index} run {run_index} lane1",
                )

                timings_us.append(elapsed_us)

            write_u32le(
                result_root / f"{name0}.bin",
                actual0,
            )

            tower_products_verified += raw_product_count

            if tower1_real:
                write_u32le(
                    result_root / f"{name1}.bin",
                    actual1,
                )

                tower_products_verified += raw_product_count

            median_us = statistics.median(timings_us)

            raw_product_rate = (
                raw_product_count
                * 1_000_000.0
                / median_us
            )

            towers_label = (
                f"{tower0},{tower1}"
                if tower1_real
                else f"{tower0},dup"
            )

            print(
                f"{pair_index:4d}  "
                f"{towers_label:10s}  "
                f"{profile_us:10.2f}  "
                f"{median_us:9.2f}  "
                f"{median_us / ciphertext_count:13.2f}  "
                f"{raw_product_rate:14.2f}"
            )

            print(
                "      PASS exact; "
                f"warmup={warmup_us:.2f} us; "
                "runs="
                + ",".join(
                    f"{value:.2f}"
                    for value in timings_us
                )
            )

            profile_load_us_total += profile_us
            pair_median_us_total += median_us
        finally:
            send_buffer.freebuffer()
            receive_buffer.freebuffer()

    compute_us_per_ciphertext = (
        pair_median_us_total / ciphertext_count
    )

    end_to_end_us_per_ciphertext = (
        pair_median_us_total + profile_load_us_total
    ) / ciphertext_count

    compute_ciphertext_rate = (
        ciphertext_count
        * 1_000_000.0
        / pair_median_us_total
    )

    end_to_end_ciphertext_rate = (
        ciphertext_count
        * 1_000_000.0
        / (
            pair_median_us_total
            + profile_load_us_total
        )
    )

    effective_raw_dcrt_rate = (
        raw_product_count
        * 1_000_000.0
        / pair_median_us_total
    )

    effective_tower_pair_rate = (
        pair_count
        * raw_product_count
        * 1_000_000.0
        / pair_median_us_total
    )

    theoretical_pair_us = (
        BUFFERED_STEADY_CYCLES_PER_PRODUCT
        / CLOCK_HZ
        * 1_000_000.0
    )

    summary = {
        "format": "openfhe-bgvrns-ciphertext-prerelin-fpga-results-v1",
        "tower_count": tower_count,
        "tower_pair_count": pair_count,
        "ciphertext_count": ciphertext_count,
        "raw_products_per_ciphertext": raw_products_per_ciphertext,
        "raw_product_count": raw_product_count,
        "timed_runs": args.timed_runs,
        "profile_load_us_total": profile_load_us_total,
        "pair_median_us_total": pair_median_us_total,
        "compute_us_per_prerelin_ciphertext":
            compute_us_per_ciphertext,
        "end_to_end_us_per_prerelin_ciphertext":
            end_to_end_us_per_ciphertext,
        "compute_prerelin_ciphertexts_per_second":
            compute_ciphertext_rate,
        "end_to_end_prerelin_ciphertexts_per_second":
            end_to_end_ciphertext_rate,
        "effective_raw_dcrt_products_per_second":
            effective_raw_dcrt_rate,
        "effective_tower_pair_products_per_second":
            effective_tower_pair_rate,
        "theoretical_pair_us_per_product":
            theoretical_pair_us,
        "verified_tower_products":
            tower_products_verified,
    }

    (
        result_root / "summary.json"
    ).write_text(
        json.dumps(summary, indent=2) + "\n",
        encoding="utf-8",
    )

    print()
    print(
        "PASS: every FPGA raw ciphertext-component "
        "product matches OpenFHE"
    )

    print(
        "verified_tower_products="
        f"{tower_products_verified}"
    )

    print(
        "compute_us_per_pre_relinearization_ciphertext="
        f"{compute_us_per_ciphertext:.2f}"
    )

    print(
        "compute_pre_relinearization_ciphertexts_per_second="
        f"{compute_ciphertext_rate:.2f}"
    )

    print(
        "end_to_end_us_per_pre_relinearization_ciphertext="
        f"{end_to_end_us_per_ciphertext:.2f}"
    )

    print(
        "end_to_end_pre_relinearization_ciphertexts_per_second="
        f"{end_to_end_ciphertext_rate:.2f}"
    )

    print(
        "effective_raw_DCRTPoly_products_per_second="
        f"{effective_raw_dcrt_rate:.2f}"
    )

    print(
        "effective_tower_pair_products_per_second="
        f"{effective_tower_pair_rate:.2f}"
    )

    print(f"results={result_root}")


if __name__ == "__main__":
    main()
