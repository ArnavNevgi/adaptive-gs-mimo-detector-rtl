from __future__ import annotations

import argparse
import struct
import sys


REQ_HEADER = bytes([0xA5, 0x5A])
RSP_HEADER = bytes([0x5A, 0xA5])
CMD_RUN_VECTOR = 0x01

STATUS_TEXT = {
    0x00: "OK",
    0x01: "checksum error",
    0x02: "bad command",
    0x03: "bad length",
    0x04: "busy",
}


EXPECTED_IDENTITY_BITS = [0b00, 0b01, 0b11, 0b10]


def q412(value: float) -> int:
    raw = int(round(value * (1 << 12)))
    return max(-(1 << 15), min((1 << 15) - 1, raw))


def q812(value: float) -> int:
    raw = int(round(value * (1 << 12)))
    return max(-(1 << 19), min((1 << 19) - 1, raw))


def build_identity_payload() -> bytes:
    payload = bytearray()
    payload += struct.pack("<B", 2)
    payload += struct.pack("<i", q812(0.0))

    h_re = [[q412(1.0 if r == c else 0.0) for c in range(4)] for r in range(4)]
    h_im = [[q412(0.0) for _ in range(4)] for _ in range(4)]
    y = [
        (q412(1.0), q412(1.0)),
        (q412(-1.0), q412(1.0)),
        (q412(-1.0), q412(-1.0)),
        (q412(1.0), q412(-1.0)),
    ]

    for row in h_re:
        for value in row:
            payload += struct.pack("<h", value)

    for row in h_im:
        for value in row:
            payload += struct.pack("<h", value)

    for re, _ in y:
        payload += struct.pack("<h", re)

    for _, im in y:
        payload += struct.pack("<h", im)

    return bytes(payload)


def build_request(payload: bytes) -> bytes:
    length = len(payload)
    body = bytearray()
    body += struct.pack("<B", CMD_RUN_VECTOR)
    body += struct.pack("<H", length)
    body += payload
    checksum = sum(body) & 0xFF
    return REQ_HEADER + bytes(body) + bytes([checksum])


def build_response(status: int, payload: bytes) -> bytes:
    length = len(payload)
    body = bytearray()
    body += struct.pack("<B", status)
    body += struct.pack("<H", length)
    body += payload
    checksum = sum(body) & 0xFF
    return RSP_HEADER + bytes(body) + bytes([checksum])


def parse_response_frame(frame: bytes) -> tuple[int, bytes]:
    if len(frame) < 6:
        raise ValueError(f"response frame is too short: {len(frame)} byte(s)")
    if frame[0:2] != RSP_HEADER:
        raise ValueError(f"bad response header: {frame[0:2].hex(' ')}")

    status = frame[2]
    length = struct.unpack("<H", frame[3:5])[0]
    expected_len = 2 + 1 + 2 + length + 1
    if len(frame) != expected_len:
        raise ValueError(f"response frame length is {len(frame)}, expected {expected_len}")

    payload = frame[5:5 + length]
    checksum = frame[-1]
    expected = (status + (length & 0xFF) + ((length >> 8) & 0xFF) + sum(payload)) & 0xFF
    if checksum != expected:
        raise ValueError(f"bad response checksum: got 0x{checksum:02X}, expected 0x{expected:02X}")

    return status, payload


def read_exact(ser, count: int) -> bytes:
    data = ser.read(count)
    if len(data) != count:
        raise TimeoutError(f"expected {count} byte(s), received {len(data)}")
    return data


def read_response(ser) -> tuple[int, bytes]:
    window = bytearray()
    while True:
        byte = ser.read(1)
        if not byte:
            raise TimeoutError("timed out waiting for response header")
        window += byte
        if len(window) > 2:
            del window[0]
        if bytes(window) == RSP_HEADER:
            break

    status = read_exact(ser, 1)[0]
    length = struct.unpack("<H", read_exact(ser, 2))[0]
    payload = read_exact(ser, length)
    checksum = read_exact(ser, 1)[0]
    frame = RSP_HEADER + bytes([status]) + struct.pack("<H", length) + payload + bytes([checksum])

    return parse_response_frame(frame)


def decode_ok_payload(payload: bytes) -> dict:
    if len(payload) != 22:
        raise ValueError(f"OK payload length is {len(payload)}, expected 22")

    mode = payload[0]
    num_iters = payload[1]
    bits = list(payload[2:6])
    xout_re = list(struct.unpack("<hhhh", payload[6:14]))
    xout_im = list(struct.unpack("<hhhh", payload[14:22]))

    return {
        "mode": mode,
        "num_iters": num_iters,
        "bits": bits,
        "xout_re": xout_re,
        "xout_im": xout_im,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Send a MIMO vector to the ZedBoard PL UART demo")
    parser.add_argument("--port", help="Serial port, for example COM5")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--vector", choices=("identity",), default="identity")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--dry-run", action="store_true", help="Build and decode packets without opening a serial port")
    args = parser.parse_args()

    if not args.dry_run and not args.port:
        parser.error("--port is required unless --dry-run is used")

    return args


def format_bytes(data: bytes) -> str:
    return " ".join(f"{value:02X}" for value in data)


def build_sample_ok_payload() -> bytes:
    payload = bytearray()
    payload += struct.pack("<B", 0)
    payload += struct.pack("<B", 4)
    payload += bytes(EXPECTED_IDENTITY_BITS)
    payload += struct.pack("<hhhh", 4096, -4096, -4096, 4096)
    payload += struct.pack("<hhhh", 4096, 4096, -4096, -4096)
    return bytes(payload)


def run_dry_run() -> int:
    payload = build_identity_payload()
    request = build_request(payload)

    print(f"Identity payload bytes: {len(payload)}")
    print(f"Request frame bytes: {len(request)}")
    print(f"Request frame: {format_bytes(request)}")

    response = build_response(0x00, build_sample_ok_payload())
    print(f"Sample OK response frame: {format_bytes(response)}")

    try:
        status, response_payload = parse_response_frame(response)
        decoded = decode_ok_payload(response_payload)
    except ValueError as exc:
        print(f"FAIL: {exc}")
        return 1

    print(f"Decoded status: 0x{status:02X} ({STATUS_TEXT.get(status, 'unknown')})")
    print(f"Decoded mode: {decoded['mode']}")
    print(f"Decoded num_iters: {decoded['num_iters']}")
    print("Decoded bits:", " ".join(f"{value:02b}" for value in decoded["bits"]))

    if status == 0x00 and decoded["bits"] == EXPECTED_IDENTITY_BITS:
        print("PASS: dry-run identity packet and sample response decode matched expected bits")
        return 0

    print("FAIL: dry-run identity response did not match expected bits 00 01 11 10")
    return 1


def main() -> int:
    args = parse_args()

    if args.dry_run:
        return run_dry_run()

    try:
        import serial
    except ImportError:
        print("pyserial is not installed. Run: python -m pip install pyserial")
        return 1

    payload = build_identity_payload()
    request = build_request(payload)

    print(f"Opening {args.port} at {args.baud} baud")
    print(f"Request bytes: {len(request)}")

    with serial.Serial(args.port, args.baud, timeout=args.timeout) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        ser.write(request)
        ser.flush()
        status, response_payload = read_response(ser)

    print(f"Status: 0x{status:02X} ({STATUS_TEXT.get(status, 'unknown')})")
    print(f"Payload length: {len(response_payload)}")

    if status != 0:
        print("FAIL: board returned non-OK status")
        return 1

    decoded = decode_ok_payload(response_payload)
    print(f"mode: {decoded['mode']}")
    print(f"num_iters: {decoded['num_iters']}")
    print("bits:", " ".join(f"{value:02b}" for value in decoded["bits"]))
    print("xout_re:", decoded["xout_re"])
    print("xout_im:", decoded["xout_im"])

    if decoded["bits"] == EXPECTED_IDENTITY_BITS:
        print("PASS: identity vector bits match expected 00 01 11 10")
        return 0

    print("FAIL: identity vector bits do not match expected 00 01 11 10")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
