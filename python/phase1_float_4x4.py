from pathlib import Path

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt


# Phase 1 target dimensions: 4 transmit streams, 4 receive antennas.
NT = 4
NR = 4
NUM_FRAMES = 20_000
SNR_DB_LIST = list(range(0, 22, 2))
GS_ITERS = (1, 2, 4, 8, 16)
GS_NAMES = tuple(f"GS-{num_iters}" for num_iters in GS_ITERS)
DETECTOR_NAMES = ("ZF", "MMSE", *GS_NAMES)
GS_INIT = "diagonal"
RNG_SEED = 42
PLOT_PATH = Path(__file__).resolve().parents[1] / "phase1_ber_4x4.png"


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


def simulate_snr(rng, snr_db, n_tx=NT, n_rx=NR, num_frames=NUM_FRAMES):
    """Simulate one SNR point and return BER values for all detectors."""
    bit_errors = {name: 0 for name in DETECTOR_NAMES}
    total_bits = 0

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

        detected_bits = {
            "ZF": qpsk_to_bits(x_zf),
            "MMSE": qpsk_to_bits(x_mmse),
            "GS-1": qpsk_to_bits(x_gs1),
            "GS-2": qpsk_to_bits(x_gs2),
            "GS-4": qpsk_to_bits(x_gs4),
            "GS-8": qpsk_to_bits(x_gs8),
            "GS-16": qpsk_to_bits(x_gs16),
        }

        for name, bits_rx in detected_bits.items():
            bit_errors[name] += np.count_nonzero(bits_tx != bits_rx)
        total_bits += bits_tx.size

    return {name: errors / total_bits for name, errors in bit_errors.items()}


def simulate_ber(snr_db_list, n_tx=NT, n_rx=NR, num_frames=NUM_FRAMES, seed=RNG_SEED):
    """Run the complete BER simulation over all requested SNR values."""
    rng = np.random.default_rng(seed)
    ber_results = {name: [] for name in DETECTOR_NAMES}

    for snr_db in snr_db_list:
        snr_result = simulate_snr(
            rng,
            snr_db,
            n_tx=n_tx,
            n_rx=n_rx,
            num_frames=num_frames,
        )
        for name in ber_results:
            ber_results[name].append(snr_result[name])

    return ber_results


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


def _mostly_decreasing(values):
    """Monte Carlo-friendly monotonic trend check."""
    values = np.asarray(values, dtype=float)
    if values[-1] > values[0]:
        return False

    adjacent_drops = np.count_nonzero(np.diff(values) <= 1e-12)
    return adjacent_drops >= max(1, values.size - 3)


def check_trends(ber_results):
    """Return PASS/FAIL checks and practical warnings for the Phase 1 run."""
    avg_ber = {name: float(np.mean(values)) for name, values in ber_results.items()}
    gap_metrics = compute_gs_gap_metrics(SNR_DB_LIST, ber_results)
    best_avg = min(avg_ber.values())
    near_best_margin = max(1e-4, 0.10 * best_avg)
    non_decreasing_curves = [
        name for name, values in ber_results.items() if not _mostly_decreasing(values)
    ]
    avg_gaps = [gap_metrics[name]["avg_gap"] for name in GS_NAMES]

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


def recommend_adaptive_modes(gap_metrics):
    """
    Pick a conservative adaptive mode set from the measured diagonal-init gaps.

    The threshold keeps GS-8 as the strongest mode only if its average and
    high-SNR gap to MMSE are both small enough for a Phase 1 baseline.
    """
    gs8_gap_ok = (
        gap_metrics["GS-8"]["avg_gap"] <= 1.0e-2
        and gap_metrics["GS-8"]["high_snr_gap"] <= 1.0e-2
    )
    if gs8_gap_ok:
        modes = ("GS-2", "GS-4", "GS-8")
        reason = "GS-8 is close enough to MMSE to serve as the strongest mode."
    else:
        modes = ("GS-4", "GS-8", "GS-16")
        reason = "GS-8 still leaves a visible high-SNR gap, while GS-16 reduces it."
    return modes, reason


def print_adaptive_mode_recommendation(gap_metrics):
    modes, reason = recommend_adaptive_modes(gap_metrics)
    print()
    print("Adaptive mode recommendation:")
    for mode_idx, mode_name in enumerate(modes):
        print(f"- Mode {mode_idx}: {mode_name}")
    print(f"- Reason: {reason}")


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


def plot_ber(snr_db_list, ber_results, output_path=PLOT_PATH):
    plt.figure(figsize=(8, 6))
    for name, ber in ber_results.items():
        plt.semilogy(snr_db_list, ber, marker="o", linewidth=1.8, label=name)

    plt.grid(True, which="both", linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("BER")
    plt.title("4x4 QPSK MIMO Detection: ZF vs MMSE vs GS")
    plt.legend()
    plt.tight_layout()
    plt.savefig(output_path, dpi=300)
    plt.close()


def main():
    print("Phase 1 floating-point 4x4 MIMO QPSK simulation")
    print(f"NT = {NT}, NR = {NR}, frames/SNR = {NUM_FRAMES}, seed = {RNG_SEED}")
    print(f"GS initialization: {GS_INIT} (x0 = b / diag(W))")
    print(f"SNR points: {SNR_DB_LIST}")
    print()

    ber_results = simulate_ber(SNR_DB_LIST, n_tx=NT, n_rx=NR, num_frames=NUM_FRAMES)
    print_ber_table(SNR_DB_LIST, ber_results)
    gap_metrics = print_gs_gap_summary(SNR_DB_LIST, ber_results)

    checks, warnings = check_trends(ber_results)
    print_trend_summary(checks, warnings)
    print_adaptive_mode_recommendation(gap_metrics)

    plot_ber(SNR_DB_LIST, ber_results)
    print()
    print(f"Saved BER plot: {PLOT_PATH}")


if __name__ == "__main__":
    main()
