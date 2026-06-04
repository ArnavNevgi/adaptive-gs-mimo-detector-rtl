from pathlib import Path

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt


# Phase 2 target dimensions: 4 transmit streams, 4 receive antennas.
NT = 4
NR = 4
NUM_FRAMES = 20_000
SNR_DB_LIST = list(range(0, 22, 2))
GS_ITERS = (1, 2, 4, 8, 16)
GS_NAMES = tuple(f"GS-{num_iters}" for num_iters in GS_ITERS)
BASELINE_DETECTOR_NAMES = ("ZF", "MMSE", *GS_NAMES)
ADAPTIVE_DETECTOR_NAME = "Adaptive-GS"
DETECTOR_NAMES = (*BASELINE_DETECTOR_NAMES, ADAPTIVE_DETECTOR_NAME)
GS_INIT = "diagonal"
ADAPTIVE_MODE_ITERS = {
    0: 4,
    1: 8,
    2: 16,
}
ADAPTIVE_MODE_NAMES = {
    0: "GS-4",
    1: "GS-8",
    2: "GS-16",
}
ADAPTIVE_POLICIES = {
    "conservative": {
        "easy": {"snr_db": 12, "dominance": 1.8},
        "medium": {"snr_db": 6, "dominance": 1.2},
    },
    "balanced": {
        "easy": {"snr_db": 10, "dominance": 1.25},
        "medium": {"snr_db": 6, "dominance": 0.95},
    },
    "aggressive": {
        "easy": {"snr_db": 8, "dominance": 1.05},
        "medium": {"snr_db": 4, "dominance": 0.80},
    },
    "aggressive_v2": {
        "easy": {"snr_db": 10, "dominance": 0.90},
        "medium": {"snr_db": 4, "dominance": 0.75},
    },
}
POLICY_NAMES = tuple(ADAPTIVE_POLICIES)
RNG_SEED = 42
OUTPUT_DIR = Path(__file__).resolve().parents[1]
AVG_ITERS_COMPARISON_PLOT_PATH = (
    OUTPUT_DIR / "phase2_avg_iters_policy_comparison_4x4.png"
)


def policy_ber_plot_path(policy_name):
    return OUTPUT_DIR / f"phase2_ber_{policy_name}_4x4.png"


def policy_mode_distribution_plot_path(policy_name):
    return OUTPUT_DIR / f"phase2_mode_distribution_{policy_name}_4x4.png"


def qpsk_mod(bits):
    """
    Map bits to unit-energy Gray-coded QPSK symbols.

    Mapping:
        00 ->  (1 + 1j) / sqrt(2)
        01 -> (-1 + 1j) / sqrt(2)
        11 -> (-1 - 1j) / sqrt(2)
        10 ->  (1 - 1j) / sqrt(2)
    """
    bits = np.asarray(bits, dtype=np.int8)
    if bits.ndim != 1 or bits.size % 2 != 0:
        raise ValueError("QPSK modulation expects a 1-D array with an even bit count.")

    bit_pairs = bits.reshape(-1, 2)
    real = 1 - 2 * bit_pairs[:, 1]
    imag = 1 - 2 * bit_pairs[:, 0]
    return (real + 1j * imag) / np.sqrt(2)


def qpsk_demod(symbols):
    """Hard-slice QPSK symbols back to bits using the qpsk_mod mapping."""
    symbols = np.asarray(symbols)
    bits = np.empty((symbols.size, 2), dtype=np.int8)
    bits[:, 0] = (np.imag(symbols) < 0).astype(np.int8)
    bits[:, 1] = (np.real(symbols) < 0).astype(np.int8)
    return bits.reshape(-1)


def qpsk_to_bits(symbols):
    """Compatibility alias for the hard-decision QPSK slicer."""
    return qpsk_demod(symbols)


def generate_channel(rng, n_rx=NR, n_tx=NT):
    """Generate an NR x NT flat Rayleigh channel with unit-variance entries."""
    return (
        rng.standard_normal((n_rx, n_tx))
        + 1j * rng.standard_normal((n_rx, n_tx))
    ) / np.sqrt(2)


def add_awgn(rng, signal, snr_db):
    """
    Add complex AWGN for unit-power QPSK streams.

    The same noise variance is used by the MMSE and GS regularization terms.
    """
    snr_linear = 10 ** (snr_db / 10)
    noise_var = 1 / snr_linear
    noise = np.sqrt(noise_var / 2) * (
        rng.standard_normal(signal.shape) + 1j * rng.standard_normal(signal.shape)
    )
    return signal + noise, noise_var


def zf_detector(H, y):
    """Zero-forcing detector using the pseudo-inverse for numerical stability."""
    return np.linalg.pinv(H) @ y


def mmse_detector(H, y, noise_var):
    """Exact linear MMSE detector: solve (H^H H + sigma^2 I) x = H^H y."""
    n_tx = H.shape[1]
    G = H.conj().T @ H
    b = H.conj().T @ y
    W = G + noise_var * np.eye(n_tx, dtype=np.complex128)
    return np.linalg.solve(W, b)


def gs_initial_guess(W, b, init=GS_INIT):
    """Return the initial vector used before Gauss-Seidel sweeps."""
    if init == "zero":
        return np.zeros_like(b, dtype=np.complex128)
    if init == "diagonal":
        return b / np.diag(W)
    raise ValueError(f"Unsupported GS initialization: {init}")


def gs_detector(H, y, noise_var, num_iters, init=GS_INIT):
    """
    Approximate MMSE detector using Gauss-Seidel iterations.

    Solves W x = b, where W = H^H H + sigma^2 I and b = H^H y.
    The default initialization is x^(0) = D^-1 b, where D = diag(W).
    Newly updated values are used for j < i; previous-iteration values are
    used for j > i.
    """
    n_tx = H.shape[1]
    G = H.conj().T @ H
    b = H.conj().T @ y
    W = G + noise_var * np.eye(n_tx, dtype=np.complex128)
    x = gs_initial_guess(W, b, init=init)

    for _ in range(num_iters):
        x_old = x.copy()
        for i in range(n_tx):
            sum_lower = np.dot(W[i, :i], x[:i])
            sum_upper = np.dot(W[i, i + 1 :], x_old[i + 1 :])
            x[i] = (b[i] - sum_lower - sum_upper) / W[i, i]

    return x


def gs_detector_at_iters(H, y, noise_var, iter_counts=GS_ITERS, init=GS_INIT):
    """Run GS once and return detector outputs at the requested iteration counts."""
    n_tx = H.shape[1]
    G = H.conj().T @ H
    b = H.conj().T @ y
    W = G + noise_var * np.eye(n_tx, dtype=np.complex128)
    x = gs_initial_guess(W, b, init=init)

    requested = set(iter_counts)
    outputs = {}
    for iter_idx in range(1, max(requested) + 1):
        x_old = x.copy()
        for i in range(n_tx):
            sum_lower = np.dot(W[i, :i], x[:i])
            sum_upper = np.dot(W[i, i + 1 :], x_old[i + 1 :])
            x[i] = (b[i] - sum_lower - sum_upper) / W[i, i]
        if iter_idx in requested:
            outputs[iter_idx] = x.copy()

    return outputs


def channel_condition_metric(H):
    """
    Compute a simple diagonal-dominance metric from G = H^H H.

    Larger dominance usually means weaker inter-stream coupling.
    Smaller dominance usually means a harder channel for low-iteration GS.
    """
    G = H.conj().T @ H

    abs_G = np.abs(G)
    diag_sum = np.sum(np.abs(np.diag(G)))
    offdiag_sum = np.sum(abs_G) - diag_sum

    eps = 1e-12
    dominance = diag_sum / (offdiag_sum + eps)

    return {
        "G": G,
        "diag_sum": float(diag_sum),
        "offdiag_sum": float(offdiag_sum),
        "dominance": float(dominance),
    }


def select_adaptive_mode(policy_name, snr_db, dominance):
    """
    Select runtime GS iteration mode for one policy.

    Mode 0: GS-4  for easy channel
    Mode 1: GS-8  for medium channel
    Mode 2: GS-16 for hard channel
    """
    policy = ADAPTIVE_POLICIES[policy_name]
    easy = policy["easy"]
    medium = policy["medium"]

    if snr_db >= easy["snr_db"] and dominance >= easy["dominance"]:
        return 0
    if snr_db >= medium["snr_db"] and dominance >= medium["dominance"]:
        return 1
    return 2


def simulate_snr(rng, snr_db, n_tx=NT, n_rx=NR, num_frames=NUM_FRAMES):
    """Simulate one SNR point and return baseline plus per-policy adaptive BER."""
    baseline_bit_errors = {name: 0 for name in BASELINE_DETECTOR_NAMES}
    adaptive_bit_errors = {policy_name: 0 for policy_name in POLICY_NAMES}
    total_bits = 0
    mode_counts = {
        policy_name: {0: 0, 1: 0, 2: 0} for policy_name in POLICY_NAMES
    }
    total_adaptive_iters = {policy_name: 0 for policy_name in POLICY_NAMES}

    for _ in range(num_frames):
        bits_tx = rng.integers(0, 2, size=2 * n_tx, dtype=np.int8)
        x = qpsk_mod(bits_tx)

        H = generate_channel(rng, n_rx=n_rx, n_tx=n_tx)
        y_clean = H @ x
        y, noise_var = add_awgn(rng, y_clean, snr_db)

        x_zf = zf_detector(H, y)
        x_mmse = mmse_detector(H, y, noise_var)
        gs_outputs = gs_detector_at_iters(H, y, noise_var)
        x_gs1 = gs_outputs[1]
        x_gs2 = gs_outputs[2]
        x_gs4 = gs_outputs[4]
        x_gs8 = gs_outputs[8]
        x_gs16 = gs_outputs[16]

        metric = channel_condition_metric(H)

        baseline_detected_bits = {
            "ZF": qpsk_to_bits(x_zf),
            "MMSE": qpsk_to_bits(x_mmse),
            "GS-1": qpsk_to_bits(x_gs1),
            "GS-2": qpsk_to_bits(x_gs2),
            "GS-4": qpsk_to_bits(x_gs4),
            "GS-8": qpsk_to_bits(x_gs8),
            "GS-16": qpsk_to_bits(x_gs16),
        }

        for name, bits_rx in baseline_detected_bits.items():
            baseline_bit_errors[name] += np.count_nonzero(bits_tx != bits_rx)

        for policy_name in POLICY_NAMES:
            mode = select_adaptive_mode(policy_name, snr_db, metric["dominance"])
            adaptive_iters = ADAPTIVE_MODE_ITERS[mode]
            x_adaptive = gs_outputs[adaptive_iters]

            mode_counts[policy_name][mode] += 1
            total_adaptive_iters[policy_name] += adaptive_iters
            adaptive_bit_errors[policy_name] += np.count_nonzero(
                bits_tx != qpsk_to_bits(x_adaptive)
            )

        total_bits += bits_tx.size

    baseline_ber = {
        name: errors / total_bits for name, errors in baseline_bit_errors.items()
    }
    adaptive_ber = {
        policy_name: errors / total_bits
        for policy_name, errors in adaptive_bit_errors.items()
    }
    adaptive_stats = {}

    for policy_name in POLICY_NAMES:
        adaptive_stats[policy_name] = {
            "avg_iters": total_adaptive_iters[policy_name] / num_frames,
            "mode_counts": mode_counts[policy_name],
            "mode_fraction": {
                mode: count / num_frames
                for mode, count in mode_counts[policy_name].items()
            },
        }

    return baseline_ber, adaptive_ber, adaptive_stats


def simulate_ber(snr_db_list, n_tx=NT, n_rx=NR, num_frames=NUM_FRAMES, seed=RNG_SEED):
    """Run the complete BER simulation over all requested SNR values."""
    rng = np.random.default_rng(seed)
    baseline_ber_results = {name: [] for name in BASELINE_DETECTOR_NAMES}
    policy_results = {
        policy_name: {
            "ber": {name: [] for name in DETECTOR_NAMES},
            "adaptive_summary": {
                "avg_iters": [],
                "mode_fraction": {0: [], 1: [], 2: []},
            },
        }
        for policy_name in POLICY_NAMES
    }

    for snr_db in snr_db_list:
        baseline_ber, adaptive_ber, adaptive_stats = simulate_snr(
            rng,
            snr_db,
            n_tx=n_tx,
            n_rx=n_rx,
            num_frames=num_frames,
        )
        for name in baseline_ber_results:
            baseline_ber_results[name].append(baseline_ber[name])

        for policy_name in POLICY_NAMES:
            policy_ber = policy_results[policy_name]["ber"]
            for name in BASELINE_DETECTOR_NAMES:
                policy_ber[name].append(baseline_ber[name])
            policy_ber[ADAPTIVE_DETECTOR_NAME].append(adaptive_ber[policy_name])

            adaptive_summary = policy_results[policy_name]["adaptive_summary"]
            adaptive_summary["avg_iters"].append(
                adaptive_stats[policy_name]["avg_iters"]
            )
            for mode in (0, 1, 2):
                adaptive_summary["mode_fraction"][mode].append(
                    adaptive_stats[policy_name]["mode_fraction"][mode]
                )

    return baseline_ber_results, policy_results


def print_ber_table(snr_db_list, ber_results):
    """Print a compact BER table."""
    names = list(ber_results)
    print("BER table")
    print("SNR(dB) " + " ".join(f"{name:>12}" for name in names))
    for idx, snr_db in enumerate(snr_db_list):
        values = " ".join(f"{ber_results[name][idx]:12.5e}" for name in names)
        print(f"{snr_db:7d} {values}")


def compute_gs_gap_metrics(snr_db_list, ber_results):
    """Compute BER gap metrics between each GS curve and exact MMSE."""
    mmse = np.asarray(ber_results["MMSE"], dtype=float)
    high_snr_count = min(3, len(snr_db_list))
    metrics = {}

    for name in GS_NAMES:
        ber = np.asarray(ber_results[name], dtype=float)
        gap = ber - mmse
        metrics[name] = {
            "avg_ber": float(np.mean(ber)),
            "avg_gap": float(np.mean(gap)),
            "high_snr_ber": float(np.mean(ber[-high_snr_count:])),
            "high_snr_gap": float(np.mean(gap[-high_snr_count:])),
            "final_ber": float(ber[-1]),
            "final_gap": float(gap[-1]),
        }

    return metrics


def print_gs_gap_summary(snr_db_list, ber_results):
    metrics = compute_gs_gap_metrics(snr_db_list, ber_results)
    print()
    print("GS/MMSE gap summary")
    print(
        "Detector "
        f"{'Avg BER':>12} "
        f"{'Avg gap':>12} "
        f"{'High-SNR BER':>14} "
        f"{'High-SNR gap':>14} "
        f"{'Final gap':>12}"
    )
    for name in GS_NAMES:
        row = metrics[name]
        print(
            f"{name:>8} "
            f"{row['avg_ber']:12.5e} "
            f"{row['avg_gap']:12.5e} "
            f"{row['high_snr_ber']:14.5e} "
            f"{row['high_snr_gap']:14.5e} "
            f"{row['final_gap']:12.5e}"
        )
    return metrics


def compute_policy_metrics(ber_results, adaptive_summary):
    adaptive = np.asarray(ber_results[ADAPTIVE_DETECTOR_NAME], dtype=float)
    gs16 = np.asarray(ber_results["GS-16"], dtype=float)
    gap = adaptive - gs16
    avg_iters = float(np.mean(adaptive_summary["avg_iters"]))
    avg_mode_fraction = {
        mode: float(np.mean(adaptive_summary["mode_fraction"][mode]))
        for mode in (0, 1, 2)
    }

    return {
        "avg_ber_gap_vs_gs16": float(np.mean(gap)),
        "final_ber_gap_vs_gs16": float(gap[-1]),
        "avg_iters": avg_iters,
        "saving_vs_gs16": (16 - avg_iters) / 16 * 100,
        "avg_mode_fraction": avg_mode_fraction,
    }


def print_policy_comparison_summary(policy_results):
    print()
    print("Policy comparison summary")
    print(
        f"{'Policy':>13} "
        f"{'Avg BER gap':>13} "
        f"{'Avg iters':>10} "
        f"{'Saving':>9} "
        f"{'Avg M0 GS-4':>12} "
        f"{'Avg M1 GS-8':>12} "
        f"{'Avg M2 GS-16':>13}"
    )
    for policy_name in POLICY_NAMES:
        result = policy_results[policy_name]
        metrics = compute_policy_metrics(
            result["ber"], result["adaptive_summary"]
        )
        mode_fraction = metrics["avg_mode_fraction"]
        print(
            f"{policy_name:>13} "
            f"{metrics['avg_ber_gap_vs_gs16']:13.5e} "
            f"{metrics['avg_iters']:10.3f} "
            f"{metrics['saving_vs_gs16']:8.2f}% "
            f"{mode_fraction[0]:12.3f} "
            f"{mode_fraction[1]:12.3f} "
            f"{mode_fraction[2]:13.3f}"
        )


def print_adaptive_summary(snr_db_list, adaptive_summary, policy_name=None):
    print()
    title = "Adaptive GS summary"
    if policy_name is not None:
        title += f" ({policy_name})"
    print(title)
    print(
        f"{'SNR(dB)':>7} "
        f"{'Avg iters':>10} "
        f"{'Mode0 GS-4':>12} "
        f"{'Mode1 GS-8':>12} "
        f"{'Mode2 GS-16':>13} "
        f"{'Saving vs GS-16':>16}"
    )

    for idx, snr_db in enumerate(snr_db_list):
        avg_iters = adaptive_summary["avg_iters"][idx]
        saving = (16 - avg_iters) / 16 * 100

        m0 = adaptive_summary["mode_fraction"][0][idx]
        m1 = adaptive_summary["mode_fraction"][1][idx]
        m2 = adaptive_summary["mode_fraction"][2][idx]

        print(
            f"{snr_db:7d} "
            f"{avg_iters:10.3f} "
            f"{m0:12.3f} "
            f"{m1:12.3f} "
            f"{m2:13.3f} "
            f"{saving:16.2f}%"
        )


def print_adaptive_gap_summary(snr_db_list, ber_results, adaptive_summary, policy_name):
    adaptive = np.asarray(ber_results[ADAPTIVE_DETECTOR_NAME], dtype=float)
    gs16 = np.asarray(ber_results["GS-16"], dtype=float)
    gap = adaptive - gs16
    metrics = compute_policy_metrics(ber_results, adaptive_summary)

    print()
    print(f"Adaptive-GS vs fixed GS-16 ({policy_name})")
    print(f"{'SNR(dB)':>7} {'Adaptive BER':>14} {'GS-16 BER':>12} {'BER gap':>12}")
    for idx, snr_db in enumerate(snr_db_list):
        print(
            f"{snr_db:7d} "
            f"{adaptive[idx]:14.5e} "
            f"{gs16[idx]:12.5e} "
            f"{gap[idx]:12.5e}"
        )
    print()
    print(f"- Average BER gap: {metrics['avg_ber_gap_vs_gs16']:.5e}")
    print(f"- Final-SNR BER gap: {metrics['final_ber_gap_vs_gs16']:.5e}")
    print(f"- Average adaptive iterations: {metrics['avg_iters']:.3f}")
    print(f"- Iteration saving vs fixed GS-16: {metrics['saving_vs_gs16']:.2f}%")


def _mostly_decreasing(values):
    """Monte Carlo-friendly monotonic trend check."""
    values = np.asarray(values, dtype=float)
    if values[-1] > values[0]:
        return False

    adjacent_drops = np.count_nonzero(np.diff(values) <= 1e-12)
    return adjacent_drops >= max(1, values.size - 3)


def check_trends(ber_results, adaptive_summary):
    """Return PASS/FAIL checks and practical warnings for the Phase 2 run."""
    avg_ber = {name: float(np.mean(values)) for name, values in ber_results.items()}
    gap_metrics = compute_gs_gap_metrics(SNR_DB_LIST, ber_results)
    best_avg = min(avg_ber.values())
    near_best_margin = max(1e-4, 0.10 * best_avg)
    non_decreasing_curves = [
        name for name, values in ber_results.items() if not _mostly_decreasing(values)
    ]
    avg_gaps = [gap_metrics[name]["avg_gap"] for name in GS_NAMES]
    avg_adaptive_iters = float(np.mean(adaptive_summary["avg_iters"]))
    adaptive_gap_to_gs16 = float(
        np.mean(np.asarray(ber_results["Adaptive-GS"]) - np.asarray(ber_results["GS-16"]))
    )

    checks = {
        "BER decreases with SNR": not non_decreasing_curves,
        "GS-4 better than GS-1": avg_ber["GS-4"] <= avg_ber["GS-1"],
        "GS-4 better than GS-2": avg_ber["GS-4"] <= avg_ber["GS-2"],
        "GS-8 closer to MMSE than GS-4": gap_metrics["GS-8"]["avg_gap"]
        <= gap_metrics["GS-4"]["avg_gap"],
        "GS-16 high-SNR floor lower than GS-8": gap_metrics["GS-16"][
            "high_snr_ber"
        ]
        <= gap_metrics["GS-8"]["high_snr_ber"],
        "Average GS/MMSE gap improves with iterations": all(
            later <= earlier for earlier, later in zip(avg_gaps, avg_gaps[1:])
        ),
        "Adaptive-GS better than fixed GS-4": avg_ber["Adaptive-GS"] <= avg_ber["GS-4"],
        "Adaptive-GS better than fixed GS-8": avg_ber["Adaptive-GS"] <= avg_ber["GS-8"],
        "Adaptive-GS close to fixed GS-16": adaptive_gap_to_gs16 <= 1.0e-2,
        "Adaptive-GS saves iterations vs GS-16": avg_adaptive_iters < 16,
        "MMSE strongest or near strongest": avg_ber["MMSE"]
        <= best_avg + near_best_margin,
    }

    warnings = []
    if non_decreasing_curves:
        warnings.append(
            "The following curves are not mostly decreasing with SNR: "
            f"{', '.join(non_decreasing_curves)}. With limited "
            "Gauss-Seidel iterations in a square 4x4 channel, detector "
            "iteration error can dominate thermal noise at moderate/high SNR."
        )
    if not (checks["GS-4 better than GS-1"] and checks["GS-4 better than GS-2"]):
        warnings.append(
            "GS-4 was not consistently better than the lower GS iteration counts. "
            "For 4x4 square MIMO, weak diagonal dominance and ill-conditioned "
            "channels can limit early GS convergence."
        )
    if not checks["MMSE strongest or near strongest"]:
        warnings.append(
            "MMSE was not near the strongest average BER curve. Re-check noise "
            "variance/SNR interpretation if this persists with more frames."
        )

    return checks, warnings


def print_trend_summary(checks, warnings):
    print()
    print("Trend checks:")
    for label, passed in checks.items():
        status = "PASS" if passed else "FAIL"
        print(f"- {label}: {status}")

    if warnings:
        print()
        print("Warnings:")
        for warning in warnings:
            print(f"- {warning}")


def plot_policy_ber(snr_db_list, policy_name, ber_results):
    output_path = policy_ber_plot_path(policy_name)
    plt.figure(figsize=(8, 6))
    for name in ("MMSE", "GS-8", "GS-16", ADAPTIVE_DETECTOR_NAME):
        ber = ber_results[name]
        label = name
        if name == ADAPTIVE_DETECTOR_NAME:
            label = f"{name} ({policy_name})"
        plt.semilogy(snr_db_list, ber, marker="o", linewidth=1.8, label=label)

    plt.grid(True, which="both", linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("BER")
    plt.title(f"4x4 QPSK MIMO: Fixed/Adaptive GS ({policy_name})")
    plt.legend()
    plt.tight_layout()
    plt.savefig(output_path, dpi=300)
    plt.close()
    print(f"Saved BER plot ({policy_name}): {output_path}")


def plot_average_iterations(snr_db_list, policy_results):
    plt.figure(figsize=(8, 5))
    for policy_name in POLICY_NAMES:
        adaptive_summary = policy_results[policy_name]["adaptive_summary"]
        plt.plot(
            snr_db_list,
            adaptive_summary["avg_iters"],
            marker="o",
            linewidth=1.8,
            label=policy_name,
        )

    plt.axhline(16, linestyle="--", linewidth=1.2, label="Fixed GS-16")
    plt.axhline(8, linestyle="--", linewidth=1.2, label="Fixed GS-8")
    plt.axhline(4, linestyle="--", linewidth=1.2, label="Fixed GS-4")

    plt.grid(True, linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("Average GS iterations")
    plt.title("Adaptive GS Average Iteration Count vs SNR")
    plt.legend()
    plt.tight_layout()

    plt.savefig(AVG_ITERS_COMPARISON_PLOT_PATH, dpi=300)
    plt.close()
    print(f"Saved average-iteration comparison plot: {AVG_ITERS_COMPARISON_PLOT_PATH}")


def plot_mode_distribution(snr_db_list, policy_name, adaptive_summary):
    output_path = policy_mode_distribution_plot_path(policy_name)
    plt.figure(figsize=(8, 5))

    plt.plot(
        snr_db_list,
        adaptive_summary["mode_fraction"][0],
        marker="o",
        linewidth=1.8,
        label="Mode 0: GS-4",
    )
    plt.plot(
        snr_db_list,
        adaptive_summary["mode_fraction"][1],
        marker="o",
        linewidth=1.8,
        label="Mode 1: GS-8",
    )
    plt.plot(
        snr_db_list,
        adaptive_summary["mode_fraction"][2],
        marker="o",
        linewidth=1.8,
        label="Mode 2: GS-16",
    )

    plt.grid(True, linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("Mode fraction")
    plt.title(f"Adaptive GS Mode Distribution vs SNR ({policy_name})")
    plt.legend()
    plt.tight_layout()

    plt.savefig(output_path, dpi=300)
    plt.close()
    print(f"Saved mode-distribution plot ({policy_name}): {output_path}")


def main():
    print("Phase 2 adaptive policy comparison: floating-point 4x4 MIMO QPSK")
    print(f"NT = {NT}, NR = {NR}, frames/SNR = {NUM_FRAMES}, seed = {RNG_SEED}")
    print(f"GS initialization: {GS_INIT} (x0 = b / diag(W))")
    print("Adaptive modes: Mode 0 = GS-4, Mode 1 = GS-8, Mode 2 = GS-16")
    print(f"Policies: {', '.join(POLICY_NAMES)}")
    print(f"SNR points: {SNR_DB_LIST}")
    print()

    baseline_ber_results, policy_results = simulate_ber(
        SNR_DB_LIST, n_tx=NT, n_rx=NR, num_frames=NUM_FRAMES
    )

    print("Fixed-detector reference")
    print_ber_table(SNR_DB_LIST, baseline_ber_results)
    print_gs_gap_summary(SNR_DB_LIST, baseline_ber_results)
    print_policy_comparison_summary(policy_results)

    print()
    for policy_name in POLICY_NAMES:
        result = policy_results[policy_name]
        print("=" * 78)
        print(f"Policy: {policy_name}")
        print_ber_table(SNR_DB_LIST, result["ber"])
        print_adaptive_summary(
            SNR_DB_LIST, result["adaptive_summary"], policy_name=policy_name
        )
        print_adaptive_gap_summary(
            SNR_DB_LIST,
            result["ber"],
            result["adaptive_summary"],
            policy_name,
        )

        checks, warnings = check_trends(result["ber"], result["adaptive_summary"])
        print_trend_summary(checks, warnings)

    print()
    for policy_name in POLICY_NAMES:
        result = policy_results[policy_name]
        plot_policy_ber(SNR_DB_LIST, policy_name, result["ber"])
        plot_mode_distribution(
            SNR_DB_LIST, policy_name, result["adaptive_summary"]
        )
    plot_average_iterations(SNR_DB_LIST, policy_results)


if __name__ == "__main__":
    main()
