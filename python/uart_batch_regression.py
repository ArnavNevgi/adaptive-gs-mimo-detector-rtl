from __future__ import annotations

import argparse
import json
import struct
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

import uart_send_vector as uart


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PHASE6_SUMMARY_PATH = PROJECT_ROOT / "vectors" / "phase6_rtl_vectors" / "phase6_vectors_summary.json"
PHASE6_UART_50_SUMMARY_PATH = (
    PROJECT_ROOT / "vectors" / "phase6_rtl_vectors" / "phase6_uart_50_vectors_summary.json"
)

MODE_LABELS = {
    0: "GS-4",
    1: "GS-8",
    2: "GS-16",
}

BASIC_PHASE6_SELECTIONS = [
    ("phase6_real_nondiagonal_gs4", "real_nondiagonal_coupled_noise0_high_snr"),
    ("phase6_complex_noise_gs8", "random_rayleigh_4db_0"),
    ("phase6_complex_noise_gs16", "random_rayleigh_12db_0"),
]

PHASE6_SET_TARGETS = {
    "phase6_20": 20,
    "phase6_50": 50,
}


@dataclass(frozen=True)
class RegressionVector:
    name: str
    source: str
    source_type: str
    case_name: str
    snr_level: int
    noise_var: int
    h_re: list[list[int]]
    h_im: list[list[int]]
    y_re: list[int]
    y_im: list[int]
    expected_mode: int
    expected_num_iters: int
    expected_bits: list[int]
    expected_xout_re: list[int]
    expected_xout_im: list[int]


def identity_gs4_vector() -> RegressionVector:
    return RegressionVector(
        name="identity_gs4",
        source="hardware-validated identity vector",
        source_type="identity",
        case_name="identity_gs4",
        snr_level=2,
        noise_var=0,
        h_re=[
            [4096, 0, 0, 0],
            [0, 4096, 0, 0],
            [0, 0, 4096, 0],
            [0, 0, 0, 4096],
        ],
        h_im=[
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
        ],
        y_re=[4096, -4096, -4096, 4096],
        y_im=[4096, 4096, -4096, -4096],
        expected_mode=0,
        expected_num_iters=4,
        expected_bits=[0b00, 0b01, 0b11, 0b10],
        expected_xout_re=[4096, -4096, -4096, 4096],
        expected_xout_im=[4096, 4096, -4096, -4096],
    )


def require_int_range(label: str, value: int, low: int, high: int) -> None:
    if value < low or value > high:
        raise ValueError(f"{label}={value} is outside [{low}, {high}]")


def validate_matrix4x4(label: str, matrix: list[list[int]]) -> None:
    if len(matrix) != 4:
        raise ValueError(f"{label} has {len(matrix)} row(s), expected 4")
    for row_idx, row in enumerate(matrix):
        if len(row) != 4:
            raise ValueError(f"{label}[{row_idx}] has {len(row)} value(s), expected 4")
        for col_idx, value in enumerate(row):
            require_int_range(f"{label}[{row_idx}][{col_idx}]", int(value), -32768, 32767)


def validate_vector4(label: str, values: list[int]) -> None:
    if len(values) != 4:
        raise ValueError(f"{label} has {len(values)} value(s), expected 4")
    for idx, value in enumerate(values):
        require_int_range(f"{label}[{idx}]", int(value), -32768, 32767)


def validate_regression_vector(vector: RegressionVector) -> None:
    require_int_range("snr_level", vector.snr_level, 0, 255)
    require_int_range("noise_var", vector.noise_var, -(1 << 31), (1 << 31) - 1)
    require_int_range("expected_mode", vector.expected_mode, 0, 255)
    require_int_range("expected_num_iters", vector.expected_num_iters, 0, 255)
    validate_matrix4x4("h_re", vector.h_re)
    validate_matrix4x4("h_im", vector.h_im)
    validate_vector4("y_re", vector.y_re)
    validate_vector4("y_im", vector.y_im)
    validate_vector4("expected_xout_re", vector.expected_xout_re)
    validate_vector4("expected_xout_im", vector.expected_xout_im)
    if len(vector.expected_bits) != 4:
        raise ValueError(f"expected_bits has {len(vector.expected_bits)} value(s), expected 4")
    for idx, value in enumerate(vector.expected_bits):
        require_int_range(f"expected_bits[{idx}]", int(value), 0, 3)


def build_run_vector_payload(vector: RegressionVector) -> bytes:
    validate_regression_vector(vector)

    payload = bytearray()
    payload += struct.pack("<B", vector.snr_level)
    payload += struct.pack("<i", vector.noise_var)

    for row in vector.h_re:
        for value in row:
            payload += struct.pack("<h", value)

    for row in vector.h_im:
        for value in row:
            payload += struct.pack("<h", value)

    for value in vector.y_re:
        payload += struct.pack("<h", value)

    for value in vector.y_im:
        payload += struct.pack("<h", value)

    return bytes(payload)


def validate_request_frame(frame: bytes) -> None:
    if len(frame) < 6:
        raise ValueError(f"request frame is too short: {len(frame)} byte(s)")
    if frame[0:2] != uart.REQ_HEADER:
        raise ValueError(f"bad request header: {frame[0:2].hex(' ')}")
    if frame[2] != uart.CMD_RUN_VECTOR:
        raise ValueError(f"bad command: 0x{frame[2]:02X}")

    length = struct.unpack("<H", frame[3:5])[0]
    expected_len = 2 + 1 + 2 + length + 1
    if len(frame) != expected_len:
        raise ValueError(f"request frame length is {len(frame)}, expected {expected_len}")

    expected_checksum = sum(frame[2:-1]) & 0xFF
    if frame[-1] != expected_checksum:
        raise ValueError(
            f"bad request checksum: got 0x{frame[-1]:02X}, expected 0x{expected_checksum:02X}"
        )


def build_expected_ok_payload(vector: RegressionVector) -> bytes:
    payload = bytearray()
    payload += struct.pack("<B", vector.expected_mode)
    payload += struct.pack("<B", vector.expected_num_iters)
    payload += bytes(vector.expected_bits)
    payload += struct.pack("<hhhh", *vector.expected_xout_re)
    payload += struct.pack("<hhhh", *vector.expected_xout_im)
    return bytes(payload)


def load_phase6_summary(summary_path: Path = PHASE6_SUMMARY_PATH) -> list[dict]:
    with summary_path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise ValueError(f"{summary_path} does not contain a vector list")
    return data


def phase6_vector_by_case(
    summary: list[dict],
    case_name: str,
    name: str,
    summary_path: Path = PHASE6_SUMMARY_PATH,
) -> RegressionVector:
    for entry in summary:
        if entry.get("case_name") == case_name:
            return RegressionVector(
                name=name,
                source=f"{summary_path.relative_to(PROJECT_ROOT)}:{case_name}",
                source_type="phase6 JSON",
                case_name=case_name,
                snr_level=int(entry["snr_level"]),
                noise_var=int(entry["noise_var_int"]),
                h_re=entry["H_re"],
                h_im=entry["H_im"],
                y_re=entry["y_re"],
                y_im=entry["y_im"],
                expected_mode=int(entry["expected_mode"]),
                expected_num_iters=int(entry["expected_num_iters"]),
                expected_bits=[int(value) for value in entry["expected_bits"]],
                expected_xout_re=[int(value) for value in entry["expected_xout_re"]],
                expected_xout_im=[int(value) for value in entry["expected_xout_im"]],
            )
    raise KeyError(f"case_name {case_name!r} was not found in {summary_path}")


def load_basic_vectors() -> list[RegressionVector]:
    vectors = [identity_gs4_vector()]

    if not PHASE6_SUMMARY_PATH.exists():
        # TODO: Add deterministic generated vectors here if the Phase 6 JSON export is not available.
        print(f"WARNING: {PHASE6_SUMMARY_PATH} not found; basic set contains identity_gs4 only")
        return vectors

    summary = load_phase6_summary()
    for name, case_name in BASIC_PHASE6_SELECTIONS:
        vectors.append(phase6_vector_by_case(summary, case_name, name))

    return vectors


def phase6_default_name(case_name: str) -> str:
    return f"phase6_{case_name}"


def build_phase6_extended_set(target_count: int, summary_path: Path = PHASE6_SUMMARY_PATH) -> list[RegressionVector]:
    vectors = load_basic_vectors()

    if not summary_path.exists():
        print(f"WARNING: {summary_path} not found; selected only the available basic vectors")
        return vectors

    summary = load_phase6_summary(summary_path)
    used_cases = {
        vector.case_name
        for vector in vectors
        if vector.source_type == "phase6 JSON"
    }
    # The hardware identity vector is the first basic vector. Skip the normalized
    # Phase 6 identity entry to avoid testing two identity-like cases up front.
    used_cases.add("identity_noise0_high_snr")

    remaining_by_mode: dict[int, list[RegressionVector]] = {0: [], 1: [], 2: []}
    for entry in summary:
        case_name = str(entry.get("case_name"))
        if case_name in used_cases:
            continue
        vector = phase6_vector_by_case(summary, case_name, phase6_default_name(case_name), summary_path)
        remaining_by_mode.setdefault(vector.expected_mode, []).append(vector)

    coverage = Counter(vector.expected_mode for vector in vectors)
    while len(vectors) < target_count and any(remaining_by_mode.values()):
        available_modes = [mode for mode in (0, 1, 2) if remaining_by_mode.get(mode)]
        mode = min(available_modes, key=lambda item: (coverage[item], item))
        vector = remaining_by_mode[mode].pop(0)
        vectors.append(vector)
        coverage[vector.expected_mode] += 1

    if len(vectors) < target_count:
        print(
            f"WARNING: requested {target_count} vectors but only {len(vectors)} "
            "deterministic vectors are available after keeping the basic set first"
        )

    for mode in (0, 1, 2):
        if coverage[mode] == 0:
            print(f"WARNING: no {MODE_LABELS[mode]} vectors are available in this selection")

    if target_count >= 20 and (coverage[0] < 6 or coverage[1] < 6 or coverage[2] < 6):
        print(
            "WARNING: current Phase 6 JSON does not provide enough balanced vectors "
            f"for 6-8 per mode; selected {MODE_LABELS[0]}={coverage[0]}, "
            f"{MODE_LABELS[1]}={coverage[1]}, {MODE_LABELS[2]}={coverage[2]}"
        )

    return vectors


def select_vectors(vector_set: str, limit: int | None) -> list[RegressionVector]:
    if vector_set == "basic":
        vectors = load_basic_vectors()
    elif vector_set == "phase6_20":
        vectors = build_phase6_extended_set(PHASE6_SET_TARGETS[vector_set], PHASE6_SUMMARY_PATH)
    elif vector_set == "phase6_50":
        vectors = build_phase6_extended_set(PHASE6_SET_TARGETS[vector_set], PHASE6_UART_50_SUMMARY_PATH)
    else:
        raise ValueError(f"unsupported vector set: {vector_set}")

    if limit is not None:
        vectors = vectors[:limit]
    if not vectors:
        raise ValueError("selected vector list is empty")
    return vectors


def format_bits(bits: list[int]) -> str:
    return " ".join(f"{value:02b}" for value in bits)


def expected_dict(vector: RegressionVector) -> dict:
    return {
        "mode": vector.expected_mode,
        "num_iters": vector.expected_num_iters,
        "bits": vector.expected_bits,
        "xout_re": vector.expected_xout_re,
        "xout_im": vector.expected_xout_im,
    }


def print_expected_got(vector: RegressionVector, got: dict | None) -> None:
    expected = expected_dict(vector)
    got = got or {}
    print(f"expected mode: {expected['mode']}")
    print(f"got mode: {got.get('mode', '<none>')}")
    print(f"expected num_iters: {expected['num_iters']}")
    print(f"got num_iters: {got.get('num_iters', '<none>')}")
    print(f"expected bits: {format_bits(expected['bits'])}")
    if "bits" in got:
        print(f"got bits: {format_bits(got['bits'])}")
    else:
        print("got bits: <none>")
    print(f"expected xout_re: {expected['xout_re']}")
    print(f"got xout_re: {got.get('xout_re', '<none>')}")
    print(f"expected xout_im: {expected['xout_im']}")
    print(f"got xout_im: {got.get('xout_im', '<none>')}")


def compare_result(vector: RegressionVector, got: dict | None) -> bool:
    if got is None:
        return False

    expected = expected_dict(vector)
    # Exact xout matching is intentional for this first controlled hardware regression.
    # A tolerance can be added here later if future vectors require it.
    return (
        got["mode"] == expected["mode"]
        and got["num_iters"] == expected["num_iters"]
        and got["bits"] == expected["bits"]
        and got["xout_re"] == expected["xout_re"]
        and got["xout_im"] == expected["xout_im"]
    )


def print_summary(passed: int, total: int, vectors: list[RegressionVector]) -> None:
    print("")
    print(f"Total: {passed}/{total} PASS")
    coverage = Counter(vector.expected_mode for vector in vectors)
    print("Mode coverage:")
    print(f"GS-4: {coverage[0]}")
    print(f"GS-8: {coverage[1]}")
    print(f"GS-16: {coverage[2]}")
    source_coverage = Counter(vector.source_type for vector in vectors)
    print("Vector source coverage:")
    print(f"identity: {source_coverage['identity']}")
    print(f"phase6 JSON: {source_coverage['phase6 JSON']}")


def run_dry_run(vectors: list[RegressionVector]) -> int:
    passed = 0
    total = len(vectors)

    for idx, vector in enumerate(vectors, start=1):
        print("")
        print(f"Running vector {idx}/{total}: {vector.name}")
        print(f"source: {vector.source}")

        try:
            payload = build_run_vector_payload(vector)
            request = uart.build_request(payload)
            validate_request_frame(request)
            response = uart.build_response(0x00, build_expected_ok_payload(vector))
            status, response_payload = uart.parse_response_frame(response)
            decoded = uart.decode_ok_payload(response_payload)
        except Exception as exc:
            print(f"FAIL: dry-run packet construction/decode failed: {exc}")
            print_expected_got(vector, None)
            continue

        print(f"payload bytes: {len(payload)}")
        print(f"request bytes: {len(request)}")
        print(f"request frame: {uart.format_bytes(request)}")
        print(f"simulated response status: 0x{status:02X} ({uart.STATUS_TEXT.get(status, 'unknown')})")
        print_expected_got(vector, decoded)

        if status == 0x00 and compare_result(vector, decoded):
            print("PASS")
            passed += 1
        else:
            print("FAIL")

    print_summary(passed, total, vectors)
    return 0 if passed == total else 1


def run_hardware(args: argparse.Namespace, vectors: list[RegressionVector]) -> int:
    try:
        import serial
    except ImportError:
        print("pyserial is not installed. Run: python -m pip install pyserial")
        return 1

    passed = 0
    total = len(vectors)

    print(f"Opening {args.port} at {args.baud} baud")
    with serial.Serial(args.port, args.baud, timeout=args.timeout) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        for idx, vector in enumerate(vectors, start=1):
            print("")
            print(f"Running vector {idx}/{total}: {vector.name}")
            print(f"source: {vector.source}")

            try:
                payload = build_run_vector_payload(vector)
                request = uart.build_request(payload)
                validate_request_frame(request)
                print(f"request bytes: {len(request)}")
                ser.write(request)
                ser.flush()
                status, response_payload = uart.read_response(ser)
            except Exception as exc:
                print(f"FAIL: {exc}")
                print_expected_got(vector, None)
                print_summary(passed, total, vectors)
                return 1

            print(f"status: 0x{status:02X} ({uart.STATUS_TEXT.get(status, 'unknown')})")
            print(f"payload length: {len(response_payload)}")

            if status != 0x00:
                print("FAIL: board returned non-OK status")
                print_expected_got(vector, None)
                continue

            try:
                decoded = uart.decode_ok_payload(response_payload)
            except Exception as exc:
                print(f"FAIL: response decode failed: {exc}")
                print_expected_got(vector, None)
                continue

            print_expected_got(vector, decoded)
            if compare_result(vector, decoded):
                print("PASS")
                passed += 1
            else:
                print("FAIL")

    print_summary(passed, total, vectors)
    return 0 if passed == total else 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a deterministic UART MIMO hardware regression")
    parser.add_argument("--port", help="Serial port, for example COM5")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--dry-run", action="store_true", help="Build/decode packets without opening UART")
    parser.add_argument("--limit", type=int, help="Run only the first N vectors")
    parser.add_argument("--vector-set", choices=("basic", "phase6_20", "phase6_50"), default="basic")
    parser.add_argument("--timeout", type=float, default=5.0)
    args = parser.parse_args()

    if args.limit is not None and args.limit <= 0:
        parser.error("--limit must be greater than zero")
    if not args.dry_run and not args.port:
        parser.error("--port is required unless --dry-run is used")

    return args


def main() -> int:
    args = parse_args()

    try:
        vectors = select_vectors(args.vector_set, args.limit)
    except Exception as exc:
        print(f"FAIL: {exc}")
        return 1

    print(f"Vector set: {args.vector_set}")
    print(f"Selected vectors: {len(vectors)}")

    if args.dry_run:
        return run_dry_run(vectors)

    return run_hardware(args, vectors)


if __name__ == "__main__":
    raise SystemExit(main())
