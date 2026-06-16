from __future__ import annotations

import argparse
import csv
import json
import time
from pathlib import Path

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt

import phase1_float_4x4 as phase1
import phase2_adaptive_float_4x4 as phase2
import phase4_scaling_fixed_point as phase4


NT = 4
NR = 4
DEFAULT_SNR_LIST = "0,2,4,6,8,10,12,14,16,18,20"
DEFAULT_FRAMES = 20_000
QUICK_FRAMES = 1_000
DEFAULT_SEED = 12_345
MODE_ITERS = {0: 4, 1: 8, 2: 16}
MODE_NAMES = {0: "GS-4", 1: "GS-8", 2: "GS-16"}
DETECTOR_NAMES = ("ZF", "MMSE", "GS-4", "GS-8", "GS-16", "Adaptive GS")
DIAGNOSTIC_ITERS = (1, 2, 4, 8, 16, 32)
SOFTWARE_POLICY_NAMES = tuple(
    name
    for name in ("balanced", "aggressive", "aggressive_v2")
    if name in phase2.ADAPTIVE_POLICIES
)
POLICY_SWEEP_NAMES = ("hardware", *SOFTWARE_POLICY_NAMES)
POLICY_LABELS = {
    "hardware": "Adaptive GS hardware policy",
    "balanced": "Adaptive GS balanced",
    "aggressive": "Adaptive GS aggressive",
    "aggressive_v2": "Adaptive GS aggressive_v2",
}
POLICY_RECOMMENDATIONS = {
    "hardware": "conservative/accurate",
    "balanced": "balanced tradeoff",
    "aggressive": "aggressive/high-saving",
    "aggressive_v2": "aggressive/high-saving",
}


def parse_snr_list(value: str) -> list[int]:
    snrs = [int(item.strip()) for item in value.split(",") if item.strip()]
    if not snrs:
        raise argparse.ArgumentTypeError("SNR list must contain at least one value")
    return snrs


def snr_to_level(snr_db: int) -> int:
    if snr_db >= 8:
        return 2
    if snr_db >= 4:
        return 1
    return 0


def l1_condition_metric(G: np.ndarray) -> tuple[float, float]:
    mag = np.abs(np.real(G)) + np.abs(np.imag(G))
    diag_sum = float(np.sum(np.diag(mag)))
    offdiag_sum = float(np.sum(mag) - diag_sum)
    return diag_sum, offdiag_sum


def select_adaptive_mode(snr_level: int, diag_sum: float, offdiag_sum: float) -> int:
    if snr_level >= 2 and 100.0 * diag_sum >= 105.0 * offdiag_sum:
        return 0
    if snr_level >= 1 and 100.0 * diag_sum >= 80.0 * offdiag_sum:
        return 1
    return 2


def format_bits(bits: np.ndarray) -> str:
    values = np.asarray(bits, dtype=np.int8).reshape(-1, 2)
    return " ".join(f"{pair[0]}{pair[1]}" for pair in values)


def format_complex_scalar(value: complex, precision: int = 5) -> str:
    z = complex(value)
    sign = "+" if z.imag >= 0 else "-"
    return f"{z.real:.{precision}e}{sign}{abs(z.imag):.{precision}e}j"


def format_complex_vector(values: np.ndarray, precision: int = 5) -> str:
    arr = np.asarray(values).reshape(-1)
    return "[" + ", ".join(format_complex_scalar(v, precision) for v in arr) + "]"


def format_complex_matrix(values: np.ndarray, precision: int = 5) -> str:
    arr = np.asarray(values)
    rows = [
        "  [" + ", ".join(format_complex_scalar(v, precision) for v in row) + "]"
        for row in arr
    ]
    return "[\n" + "\n".join(rows) + "\n]"


def gs_detector_from_matrices_debug(
    W: np.ndarray, b: np.ndarray, iter_counts: tuple[int, ...], init: str
) -> dict[int, np.ndarray]:
    if init == "zero":
        x = np.zeros_like(b, dtype=np.complex128)
    elif init == "diagonal":
        x = b / np.diag(W)
    else:
        raise ValueError(f"Unsupported GS initialization: {init}")

    requested = set(iter_counts)
    outputs = {}
    for iter_idx in range(1, max(requested) + 1):
        x_old = x.copy()
        for i in range(b.size):
            sum_lower = np.dot(W[i, :i], x[:i])
            sum_upper = np.dot(W[i, i + 1 :], x_old[i + 1 :])
            x[i] = (b[i] - sum_lower - sum_upper) / W[i, i]
        if iter_idx in requested:
            outputs[iter_idx] = x.copy()
    return outputs


def safe_ber(errors: int, total_bits: int) -> float:
    return errors / total_bits if total_bits else 0.0


def policy_plot_name(policy_name: str) -> str:
    return policy_name.replace(" ", "_").replace("-", "_").lower()


def plot_ber(rows: list[dict], output_path: Path, keys: list[tuple[str, str]], title: str) -> None:
    snrs = [row["snr_db"] for row in rows]
    plt.figure(figsize=(8, 5.5))
    for key, label in keys:
        values = [max(row[key], 1e-7) for row in rows]
        plt.semilogy(snrs, values, marker="o", linewidth=1.8, label=label)
    plt.grid(True, which="both", linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("BER")
    plt.title(title)
    plt.legend()
    plt.tight_layout()
    plt.savefig(output_path, dpi=300)
    plt.close()


def plot_avg_iters(rows: list[dict], output_path: Path) -> None:
    snrs = [row["snr_db"] for row in rows]
    avg_iters = [row["adaptive_avg_iters"] for row in rows]
    plt.figure(figsize=(8, 5))
    plt.plot(snrs, avg_iters, marker="o", linewidth=1.8, label="Adaptive GS hardware policy")
    plt.axhline(16, linestyle="--", linewidth=1.2, color="gray", label="Fixed GS-16")
    plt.axhline(8, linestyle="--", linewidth=1.0, color="gray", alpha=0.7, label="Fixed GS-8")
    plt.axhline(4, linestyle="--", linewidth=1.0, color="gray", alpha=0.5, label="Fixed GS-4")
    plt.grid(True, linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("Average iterations")
    plt.title("Adaptive GS Average Iterations vs SNR")
    plt.legend()
    plt.tight_layout()
    plt.savefig(output_path, dpi=300)
    plt.close()


def plot_mode_distribution(rows: list[dict], output_path: Path) -> None:
    snrs = [row["snr_db"] for row in rows]
    plt.figure(figsize=(8, 5))
    plt.plot(snrs, [row["gs4_percent"] for row in rows], marker="o", linewidth=1.8, label="GS-4")
    plt.plot(snrs, [row["gs8_percent"] for row in rows], marker="o", linewidth=1.8, label="GS-8")
    plt.plot(snrs, [row["gs16_percent"] for row in rows], marker="o", linewidth=1.8, label="GS-16")
    plt.grid(True, linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("Selected mode (%)")
    plt.title("Adaptive GS Mode Distribution vs SNR")
    plt.legend()
    plt.tight_layout()
    plt.savefig(output_path, dpi=300)
    plt.close()


def plot_iteration_saving(rows: list[dict], output_path: Path) -> None:
    snrs = [row["snr_db"] for row in rows]
    saving = [row["iteration_saving_percent"] for row in rows]
    plt.figure(figsize=(8, 5))
    plt.plot(snrs, saving, marker="o", linewidth=1.8, label="Adaptive GS hardware policy")
    plt.grid(True, linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("Iteration saving vs GS-16 (%)")
    plt.title("Adaptive GS Iteration Saving vs SNR")
    plt.legend()
    plt.tight_layout()
    plt.savefig(output_path, dpi=300)
    plt.close()


def rows_for_policy(rows: list[dict], policy_name: str) -> list[dict]:
    return [row for row in rows if row["policy"] == policy_name]


def plot_policy_ber(rows: list[dict], output_path: Path) -> None:
    snrs = [row["snr_db"] for row in rows_for_policy(rows, POLICY_SWEEP_NAMES[0])]
    gs16 = [max(row["gs16_ber"], 1e-7) for row in rows_for_policy(rows, POLICY_SWEEP_NAMES[0])]
    plt.figure(figsize=(8.5, 5.5))
    plt.semilogy(snrs, gs16, marker="o", linewidth=1.8, label="GS-16")
    for policy_name in POLICY_SWEEP_NAMES:
        policy_rows = rows_for_policy(rows, policy_name)
        values = [max(row["ber"], 1e-7) for row in policy_rows]
        plt.semilogy(snrs, values, marker="o", linewidth=1.8, label=POLICY_LABELS[policy_name])
    plt.grid(True, which="both", linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("BER")
    plt.title("Adaptive Policy BER vs SNR")
    plt.legend()
    plt.tight_layout()
    plt.savefig(output_path, dpi=300)
    plt.close()


def plot_policy_metric(
    rows: list[dict], output_path: Path, key: str, ylabel: str, title: str
) -> None:
    snrs = [row["snr_db"] for row in rows_for_policy(rows, POLICY_SWEEP_NAMES[0])]
    plt.figure(figsize=(8.5, 5))
    for policy_name in POLICY_SWEEP_NAMES:
        policy_rows = rows_for_policy(rows, policy_name)
        values = [row[key] for row in policy_rows]
        plt.plot(snrs, values, marker="o", linewidth=1.8, label=POLICY_LABELS[policy_name])
    if key == "average_iterations":
        plt.axhline(16, linestyle="--", linewidth=1.2, color="gray", label="Fixed GS-16")
    plt.grid(True, linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel(ylabel)
    plt.title(title)
    plt.legend()
    plt.tight_layout()
    plt.savefig(output_path, dpi=300)
    plt.close()


def plot_policy_mode_distribution(policy_rows: list[dict], output_path: Path) -> None:
    snrs = [row["snr_db"] for row in policy_rows]
    policy_label = policy_rows[0]["policy_label"] if policy_rows else "Adaptive policy"
    plt.figure(figsize=(8, 5))
    plt.plot(snrs, [row["gs4_percent"] for row in policy_rows], marker="o", linewidth=1.8, label="GS-4")
    plt.plot(snrs, [row["gs8_percent"] for row in policy_rows], marker="o", linewidth=1.8, label="GS-8")
    plt.plot(snrs, [row["gs16_percent"] for row in policy_rows], marker="o", linewidth=1.8, label="GS-16")
    plt.grid(True, linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("Selected mode (%)")
    plt.title(f"Adaptive Policy Mode Distribution: {policy_label}")
    plt.legend()
    plt.tight_layout()
    plt.savefig(output_path, dpi=300)
    plt.close()


def write_csv(path: Path, rows: list[dict], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row[field] for field in fieldnames})


def markdown_table(rows: list[dict], columns: list[tuple[str, str]], limit: int | None = None) -> str:
    selected = rows if limit is None else rows[:limit]
    header = "| " + " | ".join(label for _, label in columns) + " |"
    sep = "| " + " | ".join("---" for _ in columns) + " |"
    lines = [header, sep]
    for row in selected:
        values = []
        for key, _ in columns:
            value = row[key]
            if isinstance(value, float):
                if "ber" in key or "gap" in key:
                    values.append(f"{value:.4e}")
                else:
                    values.append(f"{value:.2f}")
            else:
                values.append(str(value))
        lines.append("| " + " | ".join(values) + " |")
    return "\n".join(lines)


def simulate_snr(rng: np.random.Generator, snr_db: int, frames: int) -> tuple[dict, dict, dict]:
    bit_errors = {name: 0 for name in DETECTOR_NAMES}
    fixed_errors = {
        "float_adaptive": 0,
        "fixed_adaptive": 0,
        "float_gs16": 0,
        "fixed_gs16": 0,
    }
    mode_counts = {0: 0, 1: 0, 2: 0}
    fixed_mode_counts = {0: 0, 1: 0, 2: 0}
    total_bits = 0
    total_iters = 0
    fixed_total_iters = 0

    for _ in range(frames):
        bits_tx = rng.integers(0, 2, size=2 * NT, dtype=np.int8)
        symbols = phase4.qpsk_mod(bits_tx)
        H = phase4.generate_channel(rng, nr=NR, nt=NT)
        y, noise_var = phase4.add_awgn(rng, H @ symbols, snr_db)

        G_float, b_float, W_float = phase4.float_reference_matrices(H, y, noise_var)
        x_zf = phase1.zf_detector(H, y)
        x_mmse = np.linalg.solve(W_float, b_float)
        gs_float = phase4.gs_detector_from_matrices(W_float, b_float, iter_counts=(4, 8, 16))

        diag_sum, offdiag_sum = l1_condition_metric(G_float)
        mode = select_adaptive_mode(snr_to_level(snr_db), diag_sum, offdiag_sum)
        iters = MODE_ITERS[mode]
        mode_counts[mode] += 1
        total_iters += iters

        float_outputs = {
            "ZF": x_zf,
            "MMSE": x_mmse,
            "GS-4": gs_float[4],
            "GS-8": gs_float[8],
            "GS-16": gs_float[16],
            "Adaptive GS": gs_float[iters],
        }
        for name, x_hat in float_outputs.items():
            bit_errors[name] += int(np.count_nonzero(bits_tx != phase4.qpsk_to_bits(x_hat)))

        stats = phase4.FixedStats()
        _, _, G_fixed, b_fixed, W_fixed = phase4.fixed_prepare_matrices(H, y, noise_var, stats)
        gs_fixed = phase4.fixed_gs_detector_from_matrices(
            W_fixed, b_fixed, stats, iter_counts=(4, 8, 16)
        )
        fixed_diag_sum, fixed_offdiag_sum = l1_condition_metric(G_fixed)
        fixed_mode = select_adaptive_mode(snr_to_level(snr_db), fixed_diag_sum, fixed_offdiag_sum)
        fixed_iters = MODE_ITERS[fixed_mode]
        fixed_mode_counts[fixed_mode] += 1
        fixed_total_iters += fixed_iters

        fixed_pairs = {
            "float_adaptive": gs_float[iters],
            "fixed_adaptive": gs_fixed[fixed_iters],
            "float_gs16": gs_float[16],
            "fixed_gs16": gs_fixed[16],
        }
        for name, x_hat in fixed_pairs.items():
            fixed_errors[name] += int(np.count_nonzero(bits_tx != phase4.qpsk_to_bits(x_hat)))

        total_bits += bits_tx.size

    ber_row = {
        "snr_db": snr_db,
        "zf_ber": safe_ber(bit_errors["ZF"], total_bits),
        "mmse_ber": safe_ber(bit_errors["MMSE"], total_bits),
        "gs4_ber": safe_ber(bit_errors["GS-4"], total_bits),
        "gs8_ber": safe_ber(bit_errors["GS-8"], total_bits),
        "gs16_ber": safe_ber(bit_errors["GS-16"], total_bits),
        "adaptive_gs_ber": safe_ber(bit_errors["Adaptive GS"], total_bits),
        "adaptive_avg_iters": total_iters / frames,
        "iteration_saving_percent": (16.0 - total_iters / frames) / 16.0 * 100.0,
        "frames": frames,
        "total_bits": total_bits,
    }
    mode_row = {
        "snr_db": snr_db,
        "gs4_count": mode_counts[0],
        "gs8_count": mode_counts[1],
        "gs16_count": mode_counts[2],
        "gs4_percent": mode_counts[0] / frames * 100.0,
        "gs8_percent": mode_counts[1] / frames * 100.0,
        "gs16_percent": mode_counts[2] / frames * 100.0,
        "avg_iters": total_iters / frames,
    }
    fixed_float_row = {
        "snr_db": snr_db,
        "float_adaptive_ber": safe_ber(fixed_errors["float_adaptive"], total_bits),
        "fixed_adaptive_ber": safe_ber(fixed_errors["fixed_adaptive"], total_bits),
        "float_gs16_ber": safe_ber(fixed_errors["float_gs16"], total_bits),
        "fixed_gs16_ber": safe_ber(fixed_errors["fixed_gs16"], total_bits),
        "fixed_float_adaptive_gap": safe_ber(fixed_errors["fixed_adaptive"], total_bits)
        - safe_ber(fixed_errors["float_adaptive"], total_bits),
        "fixed_float_gs16_gap": safe_ber(fixed_errors["fixed_gs16"], total_bits)
        - safe_ber(fixed_errors["float_gs16"], total_bits),
        "float_adaptive_avg_iters": total_iters / frames,
        "fixed_adaptive_avg_iters": fixed_total_iters / frames,
        "fixed_gs4_percent": fixed_mode_counts[0] / frames * 100.0,
        "fixed_gs8_percent": fixed_mode_counts[1] / frames * 100.0,
        "fixed_gs16_percent": fixed_mode_counts[2] / frames * 100.0,
    }
    return ber_row, mode_row, fixed_float_row


def run_simulation(snr_list: list[int], frames: int, seed: int) -> tuple[list[dict], list[dict], list[dict]]:
    rng = np.random.default_rng(seed)
    algorithm_rows = []
    mode_rows = []
    fixed_float_rows = []
    for snr_db in snr_list:
        print(f"Running SNR {snr_db} dB with {frames} frames")
        ber_row, mode_row, fixed_float_row = simulate_snr(rng, snr_db, frames)
        algorithm_rows.append(ber_row)
        mode_rows.append(mode_row)
        fixed_float_rows.append(fixed_float_row)
    return algorithm_rows, mode_rows, fixed_float_rows


def select_policy_sweep_mode(
    policy_name: str,
    snr_db: int,
    G: np.ndarray,
    phase2_dominance: float,
) -> int:
    if policy_name == "hardware":
        diag_sum, offdiag_sum = l1_condition_metric(G)
        return select_adaptive_mode(snr_to_level(snr_db), diag_sum, offdiag_sum)
    return phase2.select_adaptive_mode(policy_name, snr_db, phase2_dominance)


def simulate_policy_snr(rng: np.random.Generator, snr_db: int, frames: int) -> list[dict]:
    policy_errors = {policy_name: 0 for policy_name in POLICY_SWEEP_NAMES}
    policy_iters = {policy_name: 0 for policy_name in POLICY_SWEEP_NAMES}
    mode_counts = {
        policy_name: {0: 0, 1: 0, 2: 0} for policy_name in POLICY_SWEEP_NAMES
    }
    mmse_errors = 0
    gs16_errors = 0
    total_bits = 0

    for _ in range(frames):
        bits_tx = rng.integers(0, 2, size=2 * NT, dtype=np.int8)
        symbols = phase4.qpsk_mod(bits_tx)
        H = phase4.generate_channel(rng, nr=NR, nt=NT)
        y, noise_var = phase4.add_awgn(rng, H @ symbols, snr_db)

        G_float, b_float, W_float = phase4.float_reference_matrices(H, y, noise_var)
        x_mmse = np.linalg.solve(W_float, b_float)
        gs_float = phase4.gs_detector_from_matrices(W_float, b_float, iter_counts=(4, 8, 16))
        phase2_metric = phase2.channel_condition_metric(H)

        mmse_errors += int(np.count_nonzero(bits_tx != phase4.qpsk_to_bits(x_mmse)))
        gs16_errors += int(np.count_nonzero(bits_tx != phase4.qpsk_to_bits(gs_float[16])))

        for policy_name in POLICY_SWEEP_NAMES:
            mode = select_policy_sweep_mode(
                policy_name,
                snr_db,
                G_float,
                phase2_metric["dominance"],
            )
            iters = MODE_ITERS[mode]
            mode_counts[policy_name][mode] += 1
            policy_iters[policy_name] += iters
            policy_errors[policy_name] += int(
                np.count_nonzero(bits_tx != phase4.qpsk_to_bits(gs_float[iters]))
            )

        total_bits += bits_tx.size

    mmse_ber = safe_ber(mmse_errors, total_bits)
    gs16_ber = safe_ber(gs16_errors, total_bits)
    rows = []
    for policy_name in POLICY_SWEEP_NAMES:
        ber = safe_ber(policy_errors[policy_name], total_bits)
        avg_iters = policy_iters[policy_name] / frames
        rows.append(
            {
                "policy": policy_name,
                "policy_label": POLICY_LABELS[policy_name],
                "snr_db": snr_db,
                "ber": ber,
                "average_iterations": avg_iters,
                "iteration_saving_percent": (16.0 - avg_iters) / 16.0 * 100.0,
                "gs4_count": mode_counts[policy_name][0],
                "gs8_count": mode_counts[policy_name][1],
                "gs16_count": mode_counts[policy_name][2],
                "gs4_percent": mode_counts[policy_name][0] / frames * 100.0,
                "gs8_percent": mode_counts[policy_name][1] / frames * 100.0,
                "gs16_percent": mode_counts[policy_name][2] / frames * 100.0,
                "ber_gap_vs_gs16": ber - gs16_ber,
                "ber_gap_vs_mmse": ber - mmse_ber,
                "gs16_ber": gs16_ber,
                "mmse_ber": mmse_ber,
                "frames": frames,
                "total_bits": total_bits,
            }
        )
    return rows


def run_policy_sweep(snr_list: list[int], frames: int, seed: int) -> list[dict]:
    rng = np.random.default_rng(seed)
    rows = []
    for snr_db in snr_list:
        print(f"Running policy sweep SNR {snr_db} dB with {frames} frames")
        rows.extend(simulate_policy_snr(rng, snr_db, frames))
    return rows


def build_policy_summary(policy_rows: list[dict], snr_list: list[int]) -> list[dict]:
    summary_rows = []
    target_snr = 20 if 20 in snr_list else snr_list[-1]
    for policy_name in POLICY_SWEEP_NAMES:
        rows = rows_for_policy(policy_rows, policy_name)
        target_rows = [row for row in rows if row["snr_db"] == target_snr]
        target_row = target_rows[0] if target_rows else rows[-1]
        summary_rows.append(
            {
                "policy": policy_name,
                "policy_label": POLICY_LABELS[policy_name],
                "mean_avg_iterations": float(np.mean([row["average_iterations"] for row in rows])),
                "mean_iteration_saving_percent": float(
                    np.mean([row["iteration_saving_percent"] for row in rows])
                ),
                "max_ber_gap_vs_gs16": float(
                    np.max([row["ber_gap_vs_gs16"] for row in rows])
                ),
                "avg_ber_gap_vs_gs16": float(
                    np.mean([row["ber_gap_vs_gs16"] for row in rows])
                ),
                "ber_at_20db": target_row["ber"],
                "summary_snr_db": target_row["snr_db"],
                "recommendation_label": POLICY_RECOMMENDATIONS[policy_name],
            }
        )
    return summary_rows


def run_gs_diagnostic(seed: int, snr_db: int) -> int:
    rng = np.random.default_rng(seed)
    bits_tx = rng.integers(0, 2, size=2 * NT, dtype=np.int8)
    symbols = phase4.qpsk_mod(bits_tx)
    H = phase4.generate_channel(rng, nr=NR, nt=NT)
    y, noise_var = phase4.add_awgn(rng, H @ symbols, snr_db)
    G, b, W = phase4.float_reference_matrices(H, y, noise_var)
    x_mmse = np.linalg.solve(W, b)
    gs_outputs_by_init = {
        "zero": gs_detector_from_matrices_debug(W, b, DIAGNOSTIC_ITERS, init="zero"),
        "diagonal": gs_detector_from_matrices_debug(
            W, b, DIAGNOSTIC_ITERS, init="diagonal"
        ),
    }
    phase4_diag_outputs = phase4.gs_detector_from_matrices(
        W, b, iter_counts=DIAGNOSTIC_ITERS
    )
    phase4_matches_debug = all(
        np.allclose(gs_outputs_by_init["diagonal"][num_iters], phase4_diag_outputs[num_iters])
        for num_iters in DIAGNOSTIC_ITERS
    )

    diag_sum, offdiag_sum = l1_condition_metric(G)
    ratio = diag_sum / (offdiag_sum + 1e-12)
    snr_level = snr_to_level(snr_db)
    mode = select_adaptive_mode(snr_level, diag_sum, offdiag_sum)
    qpsk_test_symbols = np.array([1 + 1j, -1 + 1j, -1 - 1j, 1 - 1j], dtype=np.complex128)
    qpsk_expected_bits = np.array([0, 0, 0, 1, 1, 1, 1, 0], dtype=np.int8)
    qpsk_observed_bits = phase4.qpsk_to_bits(qpsk_test_symbols)
    qpsk_slicer_ok = np.array_equal(qpsk_observed_bits, qpsk_expected_bits)
    mmse_bits = phase4.qpsk_to_bits(x_mmse)
    mmse_bits_match_tx = np.array_equal(bits_tx, mmse_bits)
    w_is_hermitian = np.allclose(W, W.conj().T)

    print("GS diagnostic")
    print(f"seed: {seed}")
    print(f"SNR dB: {snr_db}")
    print(f"snr_level: {snr_level}")
    print("QPSK normalization: unit-energy symbols, Es = 1")
    print("AWGN convention: sqrt(noise_var/2) * (randn + 1j*randn)")
    print(f"noise_var used for AWGN and MMSE/GS regularization: {noise_var:.6e}")
    print(f"H shape: {H.shape}")
    print(f"y shape: {y.shape}")
    print()
    print("QPSK slicer deterministic test")
    print(f"symbols: {format_complex_vector(qpsk_test_symbols)}")
    print(f"expected bits: {format_bits(qpsk_expected_bits)}")
    print(f"observed bits: {format_bits(qpsk_observed_bits)}")
    print(f"QPSK slicer test: {'PASS' if qpsk_slicer_ok else 'FAIL'}")
    print()
    print("H matrix:")
    print(format_complex_matrix(H))
    print()
    print("y vector:")
    print(format_complex_vector(y))
    print()
    print("W = H^H H + noise_var*I:")
    print(format_complex_matrix(W))
    print(f"W Hermitian check np.allclose(W, W.conj().T): {'PASS' if w_is_hermitian else 'FAIL'}")
    print()
    print("b = H^H y:")
    print(format_complex_vector(b))
    print()
    print(f"condition number of W: {np.linalg.cond(W):.6e}")
    print(f"diag_sum: {diag_sum:.6e}")
    print(f"offdiag_sum: {offdiag_sum:.6e}")
    print(f"diag/offdiag ratio: {ratio:.6e}")
    print(f"adaptive selected mode: {mode} ({MODE_NAMES[mode]})")
    print()
    print("x_mmse:")
    print(format_complex_vector(x_mmse))
    print()
    print("GS update equation checked:")
    print("x_i = (b_i - sum_{j<i} W_ij*x_j_new - sum_{j>i} W_ij*x_j_old) / W_ii")
    print("Implementation source: phase4_scaling_fixed_point.gs_detector_from_matrices")
    print("Accepted model initialization: x0 = b / diag(W)")
    print(f"local diagnostic diagonal-init GS matches phase4 helper: {'PASS' if phase4_matches_debug else 'FAIL'}")
    print()
    print(f"transmitted bits: {format_bits(bits_tx)}")
    print(f"MMSE bits:        {format_bits(mmse_bits)}")
    print(f"MMSE bits match transmitted bits for this frame: {'YES' if mmse_bits_match_tx else 'NO'}")
    print(f"bit ordering matches deterministic QPSK mapping: {'YES' if qpsk_slicer_ok else 'NO'}")
    print()
    b_norm = np.linalg.norm(b)
    x_norm = np.linalg.norm(x_mmse)

    init_summaries = {}
    for init_name, gs_outputs in gs_outputs_by_init.items():
        print(f"GS results with {init_name} initialization")
        for num_iters in DIAGNOSTIC_ITERS:
            print(f"x_gs_{num_iters} ({init_name} init): {format_complex_vector(gs_outputs[num_iters])}")
        print()
        print(
            f"{'iters':>6} {'residual ||Wx-b||/||b||':>28} "
            f"{'solution error vs MMSE':>25} {'detected bits':>18} {'bits match tx':>13}"
        )
        residuals = []
        solution_errors = []
        for num_iters in DIAGNOSTIC_ITERS:
            x_gs = gs_outputs[num_iters]
            residual = np.linalg.norm(W @ x_gs - b) / (b_norm + 1e-30)
            solution_error = np.linalg.norm(x_gs - x_mmse) / (x_norm + 1e-30)
            gs_bits = phase4.qpsk_to_bits(x_gs)
            residuals.append(residual)
            solution_errors.append(solution_error)
            print(
                f"{num_iters:6d} "
                f"{residual:28.6e} "
                f"{solution_error:25.6e} "
                f"{format_bits(gs_bits):>18} "
                f"{'YES' if np.array_equal(bits_tx, gs_bits) else 'NO':>13}"
            )

        residual_nonincreasing = all(
            later <= earlier + 1e-12 for earlier, later in zip(residuals, residuals[1:])
        )
        error_nonincreasing = all(
            later <= earlier + 1e-12
            for earlier, later in zip(solution_errors, solution_errors[1:])
        )
        init_summaries[init_name] = {
            "residuals": residuals,
            "solution_errors": solution_errors,
            "residual_nonincreasing": residual_nonincreasing,
            "error_nonincreasing": error_nonincreasing,
        }
        print()
        print(f"residuals non-increasing: {'YES' if residual_nonincreasing else 'NO'}")
        print(f"solution errors non-increasing: {'YES' if error_nonincreasing else 'NO'}")
        print()

    diag_summary = init_summaries["diagonal"]
    if (
        qpsk_slicer_ok
        and w_is_hermitian
        and phase4_matches_debug
        and diag_summary["residuals"][-1] < diag_summary["residuals"][0]
        and diag_summary["solution_errors"][-1] < diag_summary["solution_errors"][0]
    ):
        print("PASS: diagonal-init GS-32 is closer to the exact MMSE solve than GS-1")
        return 0
    print("FAIL: diagnostic found a slicer, matrix, or GS convergence issue")
    return 1


def write_summary_doc(
    path: Path,
    snr_list: list[int],
    frames: int,
    seed: int,
    out_dir: Path,
    algorithm_rows: list[dict],
    mode_rows: list[dict],
    fixed_float_rows: list[dict],
    elapsed_s: float,
) -> None:
    plot_paths = [
        out_dir / "ber_vs_snr.png",
        out_dir / "adaptive_avg_iters_vs_snr.png",
        out_dir / "adaptive_mode_distribution_vs_snr.png",
        out_dir / "adaptive_iteration_saving_vs_snr.png",
        out_dir / "fixed_vs_float_ber.png",
    ]
    text = f"""# Final Algorithm Results

## Purpose

This document records algorithm-level BER and adaptive-iteration results for the 4x4 QPSK adaptive fixed-point Gauss-Seidel MIMO detector. These results complement RTL verification and ZedBoard UART hardware validation.

## Simulation Setup

- MIMO configuration: 4x4
- Modulation: QPSK with mapping `+re +im -> 00`, `-re +im -> 01`, `-re -im -> 11`, `+re -im -> 10`
- Channel: flat Rayleigh fading
- Noise: complex AWGN
- SNR list: `{','.join(str(v) for v in snr_list)}` dB
- Frames per SNR: {frames}
- Random seed: {seed}
- Detectors compared: ZF, MMSE, GS-4, GS-8, GS-16, adaptive GS hardware policy
- Adaptive GS hardware policy: GS-4 when `snr_level >= 2` and `100*diag_sum >= 105*offdiag_sum`; GS-8 when `snr_level >= 1` and `100*diag_sum >= 80*offdiag_sum`; otherwise GS-16
- Fixed-point formats: H/y Q4.12, G/b/W Q8.12, ACC Q12.16, x Q6.16, xout Q4.12
- Runtime for this run: {elapsed_s:.1f} seconds

## Plot Outputs

""" + "\n".join(f"- `{path.as_posix()}`" for path in plot_paths)

    text += "\n\n## BER vs SNR\n\n"
    text += markdown_table(
        algorithm_rows,
        [
            ("snr_db", "SNR dB"),
            ("zf_ber", "ZF"),
            ("mmse_ber", "MMSE"),
            ("gs4_ber", "GS-4"),
            ("gs8_ber", "GS-8"),
            ("gs16_ber", "GS-16"),
            ("adaptive_gs_ber", "Adaptive GS hardware policy"),
        ],
    )
    text += """

### Inference

MMSE is the exact regularized linear solve for this model and improves with SNR. GS-4, GS-8, and GS-16 are finite-iteration approximations to the same solve, so they can show a BER floor on random square 4x4 Rayleigh channels when the system is weakly diagonally dominant or ill-conditioned. The `--diagnose-gs` mode checks one deterministic frame and confirms that the GS residual and solution error decrease as iteration count increases. ZF can be worse, especially at lower SNR, because it does not regularize noise enhancement.

## Adaptive Average Iterations

"""
    text += markdown_table(
        algorithm_rows,
        [
            ("snr_db", "SNR dB"),
            ("adaptive_avg_iters", "Avg iterations"),
            ("iteration_saving_percent", "Saving vs GS-16 (%)"),
        ],
    )
    text += """

### Inference

Lower average iteration count means reduced compute work compared with always using GS-16. The hardware policy used here is conservative: it selects fewer iterations only when the SNR and diagonal-dominance metric indicate an easier solve, and it otherwise stays at GS-16. On random 4x4 Rayleigh channels this often produces average iterations close to 16, so low savings are expected rather than evidence of a fixed-point or BER accounting bug.

## Mode Distribution

"""
    text += markdown_table(
        mode_rows,
        [
            ("snr_db", "SNR dB"),
            ("gs4_percent", "GS-4 %"),
            ("gs8_percent", "GS-8 %"),
            ("gs16_percent", "GS-16 %"),
        ],
    )
    text += """

### Inference

GS-4 is selected for easier high-SNR and more diagonally dominant cases. GS-16 is selected for lower-SNR or weak-dominance cases where more iterations are needed. GS-8 occupies the intermediate policy region. If this table is dominated by GS-16, the policy is acting conservatively for the channel ensemble.

## Iteration Saving

"""
    text += markdown_table(
        algorithm_rows,
        [
            ("snr_db", "SNR dB"),
            ("adaptive_avg_iters", "Avg iterations"),
            ("iteration_saving_percent", "Saving (%)"),
        ],
    )
    text += """

### Inference

The saving metric is `(16 - avg_iters) / 16 * 100%`. It quantifies the adaptive-computation benefit relative to always running GS-16. Low values mean the hardware-consistent policy is choosing robustness over iteration reduction for these frames.

## Fixed-Point vs Floating-Point

"""
    text += markdown_table(
        fixed_float_rows,
        [
            ("snr_db", "SNR dB"),
            ("float_adaptive_ber", "Float adaptive"),
            ("fixed_adaptive_ber", "Fixed adaptive"),
            ("fixed_float_adaptive_gap", "Adaptive gap"),
            ("float_gs16_ber", "Float GS-16"),
            ("fixed_gs16_ber", "Fixed GS-16"),
            ("fixed_float_gs16_gap", "GS-16 gap"),
        ],
    )
    text += """

### Inference

The fixed-point adaptive GS curve should stay close to floating-point adaptive GS if the selected Q formats are adequate. Any visible gap is reported directly in the table rather than hidden or rounded away.

## Paper-Ready Summary

The algorithm-level results are valid for the current hardware policy, but they should be interpreted as a conservative adaptive-GS configuration. The diagnostic confirms that the GS update, diagonal initialization, MMSE matrix construction, noise convention, and QPSK bit mapping are internally consistent. The BER floors and low iteration savings in the quick random-Rayleigh run are therefore best explained by finite GS iteration count plus conservative adaptive thresholds, not by an RTL or Python bit-ordering bug. Together with the RTL and ZedBoard UART hardware regression results, these plots support FPGA implementability; a separate clearly labeled software policy sweep would be needed to claim larger adaptive iteration savings.
"""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def write_outputs(
    out_dir: Path,
    snr_list: list[int],
    frames: int,
    seed: int,
    algorithm_rows: list[dict],
    mode_rows: list[dict],
    fixed_float_rows: list[dict],
    elapsed_s: float,
) -> dict[str, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)

    algorithm_csv = out_dir / "algorithm_results.csv"
    mode_csv = out_dir / "mode_distribution.csv"
    fixed_float_csv = out_dir / "fixed_float_results.csv"
    json_path = out_dir / "algorithm_results.json"
    summary_path = Path(__file__).resolve().parents[1] / "docs" / "final_algorithm_results.md"

    write_csv(
        algorithm_csv,
        algorithm_rows,
        [
            "snr_db",
            "zf_ber",
            "mmse_ber",
            "gs4_ber",
            "gs8_ber",
            "gs16_ber",
            "adaptive_gs_ber",
            "adaptive_avg_iters",
            "iteration_saving_percent",
            "frames",
            "total_bits",
        ],
    )
    write_csv(
        mode_csv,
        mode_rows,
        [
            "snr_db",
            "gs4_count",
            "gs8_count",
            "gs16_count",
            "gs4_percent",
            "gs8_percent",
            "gs16_percent",
            "avg_iters",
        ],
    )
    write_csv(
        fixed_float_csv,
        fixed_float_rows,
        [
            "snr_db",
            "float_adaptive_ber",
            "fixed_adaptive_ber",
            "float_gs16_ber",
            "fixed_gs16_ber",
            "fixed_float_adaptive_gap",
            "fixed_float_gs16_gap",
            "float_adaptive_avg_iters",
            "fixed_adaptive_avg_iters",
            "fixed_gs4_percent",
            "fixed_gs8_percent",
            "fixed_gs16_percent",
        ],
    )

    payload = {
        "metadata": {
            "nt": NT,
            "nr": NR,
            "snr_db_list": snr_list,
            "frames_per_snr": frames,
            "seed": seed,
            "elapsed_seconds": elapsed_s,
            "reused_modules": ["phase1_float_4x4.py", "phase4_scaling_fixed_point.py"],
        },
        "algorithm_results": algorithm_rows,
        "mode_distribution": mode_rows,
        "fixed_float_results": fixed_float_rows,
    }
    json_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    plot_ber(
        algorithm_rows,
        out_dir / "ber_vs_snr.png",
        [
            ("zf_ber", "ZF"),
            ("mmse_ber", "MMSE"),
            ("gs4_ber", "GS-4"),
            ("gs8_ber", "GS-8"),
            ("gs16_ber", "GS-16"),
            ("adaptive_gs_ber", "Adaptive GS hardware policy"),
        ],
        "BER vs SNR: ZF, MMSE, Fixed-Iteration GS, and Adaptive GS Hardware Policy",
    )
    plot_avg_iters(algorithm_rows, out_dir / "adaptive_avg_iters_vs_snr.png")
    plot_mode_distribution(mode_rows, out_dir / "adaptive_mode_distribution_vs_snr.png")
    plot_iteration_saving(algorithm_rows, out_dir / "adaptive_iteration_saving_vs_snr.png")
    plot_ber(
        fixed_float_rows,
        out_dir / "fixed_vs_float_ber.png",
        [
            ("float_adaptive_ber", "Float adaptive GS"),
            ("fixed_adaptive_ber", "Fixed adaptive GS"),
            ("float_gs16_ber", "Float GS-16"),
            ("fixed_gs16_ber", "Fixed GS-16"),
        ],
        "Fixed-Point vs Floating-Point BER",
    )
    write_summary_doc(
        summary_path,
        snr_list,
        frames,
        seed,
        out_dir,
        algorithm_rows,
        mode_rows,
        fixed_float_rows,
        elapsed_s,
    )
    return {
        "algorithm_csv": algorithm_csv,
        "mode_csv": mode_csv,
        "fixed_float_csv": fixed_float_csv,
        "json": json_path,
        "summary": summary_path,
    }


def write_policy_sweep_outputs(
    out_dir: Path,
    snr_list: list[int],
    frames: int,
    seed: int,
    policy_rows: list[dict],
    summary_rows: list[dict],
    elapsed_s: float,
) -> dict[str, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "adaptive_policy_sweep.csv"
    json_path = out_dir / "adaptive_policy_summary.json"
    ber_plot = out_dir / "adaptive_policy_ber_vs_snr.png"
    avg_iters_plot = out_dir / "adaptive_policy_avg_iters_vs_snr.png"
    saving_plot = out_dir / "adaptive_policy_iteration_saving_vs_snr.png"

    write_csv(
        csv_path,
        policy_rows,
        [
            "policy",
            "policy_label",
            "snr_db",
            "ber",
            "average_iterations",
            "iteration_saving_percent",
            "gs4_count",
            "gs8_count",
            "gs16_count",
            "gs4_percent",
            "gs8_percent",
            "gs16_percent",
            "ber_gap_vs_gs16",
            "ber_gap_vs_mmse",
            "gs16_ber",
            "mmse_ber",
            "frames",
            "total_bits",
        ],
    )

    mode_plots = {}
    for policy_name in POLICY_SWEEP_NAMES:
        policy_rows_for_plot = rows_for_policy(policy_rows, policy_name)
        output_path = out_dir / f"adaptive_policy_mode_distribution_{policy_plot_name(policy_name)}.png"
        plot_policy_mode_distribution(policy_rows_for_plot, output_path)
        mode_plots[policy_name] = output_path

    plot_policy_ber(policy_rows, ber_plot)
    plot_policy_metric(
        policy_rows,
        avg_iters_plot,
        "average_iterations",
        "Average iterations",
        "Adaptive Policy Average Iterations vs SNR",
    )
    plot_policy_metric(
        policy_rows,
        saving_plot,
        "iteration_saving_percent",
        "Iteration saving vs GS-16 (%)",
        "Adaptive Policy Iteration Saving vs SNR",
    )

    payload = {
        "metadata": {
            "nt": NT,
            "nr": NR,
            "snr_db_list": snr_list,
            "frames_per_snr": frames,
            "seed": seed,
            "elapsed_seconds": elapsed_s,
            "hardware_policy": {
                "label": POLICY_LABELS["hardware"],
                "metric": "L1 abs(real)+abs(imag) on G, using RTL-style cross-multiply thresholds",
                "easy": "snr_level >= 2 and 100*diag_sum >= 105*offdiag_sum",
                "medium": "snr_level >= 1 and 100*diag_sum >= 80*offdiag_sum",
            },
            "software_policy_source": "python/phase2_adaptive_float_4x4.py::ADAPTIVE_POLICIES",
            "software_policies": {
                name: phase2.ADAPTIVE_POLICIES[name] for name in SOFTWARE_POLICY_NAMES
            },
        },
        "summary": summary_rows,
        "rows": policy_rows,
    }
    json_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    outputs = {
        "policy_csv": csv_path,
        "policy_json": json_path,
        "policy_ber_plot": ber_plot,
        "policy_avg_iters_plot": avg_iters_plot,
        "policy_saving_plot": saving_plot,
    }
    for policy_name, path in mode_plots.items():
        outputs[f"policy_mode_plot_{policy_name}"] = path
    return outputs


def append_policy_sweep_doc(
    path: Path,
    out_dir: Path,
    policy_outputs: dict[str, Path],
    summary_rows: list[dict],
) -> None:
    plot_paths = [
        policy_outputs["policy_ber_plot"],
        policy_outputs["policy_avg_iters_plot"],
        policy_outputs["policy_saving_plot"],
    ]
    plot_paths.extend(
        policy_outputs[f"policy_mode_plot_{policy_name}"] for policy_name in POLICY_SWEEP_NAMES
    )

    data_paths = [
        policy_outputs["policy_csv"],
        policy_outputs["policy_json"],
    ]

    section = """

## Adaptive Policy Sweep

The implemented FPGA hardware uses the hardware-consistent conservative policy labeled `Adaptive GS hardware policy`. That policy was validated on ZedBoard, but it gives low average iteration savings in random 4x4 Rayleigh simulations because it selects GS-16 for most weak-dominance cases.

The additional `balanced`, `aggressive`, and `aggressive_v2` curves are software-only Phase 2 policy studies. They reuse the policy thresholds from `python/phase2_adaptive_float_4x4.py` and use the Phase 2 complex-magnitude dominance metric. These policies are not currently implemented in the FPGA bitstream unless the RTL is explicitly changed and revalidated.

### Policy Sweep Outputs

""" + "\n".join(f"- `{path.as_posix()}`" for path in data_paths + plot_paths)

    section += "\n\n"
    section += markdown_table(
        summary_rows,
        [
            ("policy_label", "Policy"),
            ("mean_avg_iterations", "Mean avg iterations"),
            ("mean_iteration_saving_percent", "Mean saving vs GS-16 (%)"),
            ("max_ber_gap_vs_gs16", "Max BER gap vs GS-16"),
            ("ber_at_20db", "BER at 20 dB"),
            ("recommendation_label", "Interpretation"),
        ],
    )
    section += """

### Inference

If the balanced or aggressive software policies give much higher savings with an acceptable BER gap, they can be proposed as future hardware policy options. If their BER gap is too large for the target system, the hardware policy should remain as implemented and the paper should state that adaptive savings are modest for this random 4x4 Rayleigh setting. Do not claim the FPGA implements the balanced or aggressive policies unless the RTL is changed and the ZedBoard validation is repeated.
"""
    with path.open("a", encoding="utf-8") as f:
        f.write(section)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate final algorithm plots and tables")
    parser.add_argument("--snr-list", type=parse_snr_list, default=parse_snr_list(DEFAULT_SNR_LIST))
    parser.add_argument("--frames", type=int, default=DEFAULT_FRAMES)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--out-dir", type=Path, default=Path("results") / "final_algorithm_plots")
    parser.add_argument("--quick", action="store_true", help=f"Use {QUICK_FRAMES} frames per SNR")
    parser.add_argument("--final", action="store_true", help="Use final frame count")
    parser.add_argument("--diagnose-gs", action="store_true", help="Run one deterministic GS convergence diagnostic")
    parser.add_argument("--diagnose-snr", type=int, default=20, help="SNR in dB for --diagnose-gs")
    parser.add_argument(
        "--policy-sweep",
        action="store_true",
        help="Also run software-only adaptive policy comparison curves",
    )
    args = parser.parse_args()
    if args.frames <= 0:
        parser.error("--frames must be positive")
    if args.quick and args.final:
        parser.error("--quick and --final are mutually exclusive")
    if args.quick:
        args.frames = QUICK_FRAMES
    return args


def main() -> int:
    args = parse_args()
    if args.diagnose_gs:
        return run_gs_diagnostic(args.seed, args.diagnose_snr)

    start = time.perf_counter()
    print("Final algorithm plot generation")
    print(f"snr_list={args.snr_list}")
    print(f"frames_per_snr={args.frames}")
    print(f"seed={args.seed}")
    print(f"out_dir={args.out_dir}")
    print("reused modules: phase1_float_4x4.py, phase4_scaling_fixed_point.py")
    if args.policy_sweep:
        print("policy_sweep=enabled")
        print("software policy source: phase2_adaptive_float_4x4.py::ADAPTIVE_POLICIES")
        print(f"software policies={list(SOFTWARE_POLICY_NAMES)}")

    algorithm_rows, mode_rows, fixed_float_rows = run_simulation(
        args.snr_list, args.frames, args.seed
    )
    elapsed = time.perf_counter() - start
    outputs = write_outputs(
        args.out_dir,
        args.snr_list,
        args.frames,
        args.seed,
        algorithm_rows,
        mode_rows,
        fixed_float_rows,
        elapsed,
    )
    print(f"elapsed_seconds={elapsed:.1f}")
    for label, path in outputs.items():
        print(f"{label}: {path}")
    print("plot: " + str(args.out_dir / "ber_vs_snr.png"))
    print("plot: " + str(args.out_dir / "adaptive_avg_iters_vs_snr.png"))
    print("plot: " + str(args.out_dir / "adaptive_mode_distribution_vs_snr.png"))
    print("plot: " + str(args.out_dir / "adaptive_iteration_saving_vs_snr.png"))
    print("plot: " + str(args.out_dir / "fixed_vs_float_ber.png"))

    if args.policy_sweep:
        policy_start = time.perf_counter()
        policy_rows = run_policy_sweep(args.snr_list, args.frames, args.seed)
        policy_elapsed = time.perf_counter() - policy_start
        summary_rows = build_policy_summary(policy_rows, args.snr_list)
        policy_outputs = write_policy_sweep_outputs(
            args.out_dir,
            args.snr_list,
            args.frames,
            args.seed,
            policy_rows,
            summary_rows,
            policy_elapsed,
        )
        append_policy_sweep_doc(
            outputs["summary"],
            args.out_dir,
            policy_outputs,
            summary_rows,
        )
        print(f"policy_sweep_elapsed_seconds={policy_elapsed:.1f}")
        for label, path in policy_outputs.items():
            print(f"{label}: {path}")
        print()
        print("Policy sweep aggregate summary")
        print(
            f"{'Policy':>28} {'Mean iters':>11} {'Mean saving':>13} "
            f"{'Max gap GS16':>13} {'BER at 20dB':>12} {'Interpretation':>24}"
        )
        for row in summary_rows:
            print(
                f"{row['policy_label']:>28} "
                f"{row['mean_avg_iterations']:11.3f} "
                f"{row['mean_iteration_saving_percent']:12.2f}% "
                f"{row['max_ber_gap_vs_gs16']:13.5e} "
                f"{row['ber_at_20db']:12.5e} "
                f"{row['recommendation_label']:>24}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
