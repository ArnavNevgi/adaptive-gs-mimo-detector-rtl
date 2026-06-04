from argparse import ArgumentParser
from dataclasses import dataclass, field
from pathlib import Path

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt


SNR_DB_LIST = list(range(0, 22, 2))
RNG_SEED = 42
QUICK_FRAMES = 1_000
VALIDATE_FRAMES = 3_000
GS_ITERS = (4, 8, 16)
ADAPTIVE_MODE_ITERS = {0: 4, 1: 8, 2: 16}
OUTPUT_DIR = Path(__file__).resolve().parents[1]

CONFIGS = [
    {"name": "4x4", "nr": 4, "nt": 4},
    {"name": "8x4", "nr": 8, "nt": 4},
    {"name": "8x8", "nr": 8, "nt": 8},
]


@dataclass(frozen=True)
class MimoConfig:
    name: str
    nr: int
    nt: int


@dataclass(frozen=True)
class FixedFormat:
    name: str
    total_bits: int
    frac_bits: int

    @property
    def scale(self):
        return 2**self.frac_bits

    @property
    def int_min(self):
        return -(2 ** (self.total_bits - 1))

    @property
    def int_max(self):
        return 2 ** (self.total_bits - 1) - 1


@dataclass
class FixedStats:
    saturation_count: int = 0
    overflow_count: int = 0
    nan_inf_count: int = 0
    block_saturation: dict = field(default_factory=dict)
    max_abs: dict = field(default_factory=dict)

    def record_saturation(self, block, count):
        if count <= 0:
            return
        self.saturation_count += count
        self.overflow_count += count
        self.block_saturation[block] = self.block_saturation.get(block, 0) + count

    def update_max_abs(self, name, value):
        if np.size(value) == 0:
            return
        max_value = float(np.max(np.abs(value)))
        self.max_abs[name] = max(self.max_abs.get(name, 0.0), max_value)

    def record_nan_inf(self, value):
        if not np.all(np.isfinite(value)):
            self.nan_inf_count += 1


@dataclass
class ErrorAccumulator:
    abs_sum: float = 0.0
    sq_sum: float = 0.0
    count: int = 0

    def update(self, fixed_value, float_value):
        diff = np.asarray(fixed_value) - np.asarray(float_value)
        abs_diff = np.abs(diff)
        self.abs_sum += float(np.sum(abs_diff))
        self.sq_sum += float(np.sum(abs_diff**2))
        self.count += int(abs_diff.size)

    def avg_abs(self):
        return self.abs_sum / self.count if self.count else 0.0

    def rms(self):
        return np.sqrt(self.sq_sum / self.count) if self.count else 0.0


@dataclass
class MetricAccumulator:
    diag_sum: float = 0.0
    offdiag_sum: float = 0.0
    dominance: float = 0.0
    count: int = 0

    def update(self, metric):
        self.diag_sum += metric["diag_sum"]
        self.offdiag_sum += metric["offdiag_sum"]
        self.dominance += metric["dominance"]
        self.count += 1

    def averages(self):
        if self.count == 0:
            return {"diag_sum": 0.0, "offdiag_sum": 0.0, "dominance": 0.0}
        return {
            "diag_sum": self.diag_sum / self.count,
            "offdiag_sum": self.offdiag_sum / self.count,
            "dominance": self.dominance / self.count,
        }


FMT_H = FixedFormat("Q4.12", 16, 12)
FMT_Y = FixedFormat("Q4.12", 16, 12)
FMT_G = FixedFormat("Q8.12", 20, 12)
FMT_B = FixedFormat("Q8.12", 20, 12)
FMT_W = FixedFormat("Q8.12", 20, 12)
FMT_ACC = FixedFormat("Q12.16", 28, 16)
FMT_X = FixedFormat("Q6.16", 22, 16)
FMT_X_OUT = FixedFormat("Q4.12", 16, 12)


def quantize_real(value, fmt, saturate=True, stats=None, block="quant"):
    arr = np.asarray(value, dtype=np.float64)
    raw = np.round(arr * fmt.scale)
    overflow = (raw < fmt.int_min) | (raw > fmt.int_max)
    overflow_count = int(np.count_nonzero(overflow))
    if stats is not None:
        stats.record_saturation(block, overflow_count)
    if saturate:
        raw = np.clip(raw, fmt.int_min, fmt.int_max)
    quantized = raw / fmt.scale
    if np.ndim(value) == 0:
        return float(quantized)
    return quantized


def quantize_complex(value, fmt, saturate=True, stats=None, block="quant"):
    real = quantize_real(
        np.real(value), fmt, saturate=saturate, stats=stats, block=block
    )
    imag = quantize_real(
        np.imag(value), fmt, saturate=saturate, stats=stats, block=block
    )
    return real + 1j * imag


def quantize_with_format(value, fmt, stats=None, block="quant"):
    if np.iscomplexobj(value):
        return quantize_complex(value, fmt, stats=stats, block=block)
    return quantize_real(value, fmt, stats=stats, block=block)


def fixed_add(a, b, fmt, stats=None, block="add"):
    return quantize_with_format(a + b, fmt, stats=stats, block=block)


def fixed_mul_complex(a, b, fmt, stats=None, block="mul_complex"):
    product = (np.real(a) * np.real(b) - np.imag(a) * np.imag(b)) + 1j * (
        np.real(a) * np.imag(b) + np.imag(a) * np.real(b)
    )
    return quantize_complex(product, fmt, stats=stats, block=block)


def qpsk_mod(bits):
    bits = np.asarray(bits, dtype=np.int8)
    bit_pairs = bits.reshape(-1, 2)
    real = 1 - 2 * bit_pairs[:, 1]
    imag = 1 - 2 * bit_pairs[:, 0]
    return (real + 1j * imag) / np.sqrt(2)


def qpsk_to_bits(symbols):
    symbols = np.asarray(symbols)
    bits = np.empty((symbols.size, 2), dtype=np.int8)
    bits[:, 0] = (np.imag(symbols) < 0).astype(np.int8)
    bits[:, 1] = (np.real(symbols) < 0).astype(np.int8)
    return bits.reshape(-1)


def generate_channel(rng, nr, nt):
    return (rng.standard_normal((nr, nt)) + 1j * rng.standard_normal((nr, nt))) / np.sqrt(2)


def add_awgn(rng, signal, snr_db):
    snr_linear = 10 ** (snr_db / 10)
    noise_var = 1 / snr_linear
    noise = np.sqrt(noise_var / 2) * (
        rng.standard_normal(signal.shape) + 1j * rng.standard_normal(signal.shape)
    )
    return signal + noise, noise_var


def float_reference_matrices(H, y, noise_var):
    nt = H.shape[1]
    G = H.conj().T @ H
    b = H.conj().T @ y
    W = G + noise_var * np.eye(nt, dtype=np.complex128)
    return G, b, W


def mmse_detector(H, y, noise_var):
    _, b, W = float_reference_matrices(H, y, noise_var)
    return np.linalg.solve(W, b)


def gs_detector_from_matrices(W, b, iter_counts=GS_ITERS):
    nt = b.size
    x = b / np.diag(W)
    requested = set(iter_counts)
    outputs = {}

    for iter_idx in range(1, max(requested) + 1):
        x_old = x.copy()
        for i in range(nt):
            sum_lower = np.dot(W[i, :i], x[:i])
            sum_upper = np.dot(W[i, i + 1 :], x_old[i + 1 :])
            x[i] = (b[i] - sum_lower - sum_upper) / W[i, i]
        if iter_idx in requested:
            outputs[iter_idx] = x.copy()
    return outputs


def channel_condition_metric_from_G(G):
    abs_G = np.abs(G)
    diag_sum = np.sum(np.abs(np.diag(G)))
    offdiag_sum = np.sum(abs_G) - diag_sum
    dominance = diag_sum / (offdiag_sum + 1e-12)
    return {
        "diag_sum": float(diag_sum),
        "offdiag_sum": float(offdiag_sum),
        "dominance": float(dominance),
    }


def select_adaptive_mode_aggressive(snr_db, dominance):
    if snr_db >= 8 and dominance >= 1.05:
        return 0
    if snr_db >= 4 and dominance >= 0.80:
        return 1
    return 2


def select_adaptive_mode_aggressive_rtl_friendly(snr_db, diag_sum, offdiag_sum):
    if snr_db >= 8 and 100 * diag_sum >= 105 * offdiag_sum:
        return 0
    if snr_db >= 4 and 100 * diag_sum >= 80 * offdiag_sum:
        return 1
    return 2


def fixed_prepare_matrices(H, y, noise_var, stats):
    H_q = quantize_with_format(H, FMT_H, stats=stats, block="input_quant")
    y_q = quantize_with_format(y, FMT_Y, stats=stats, block="input_quant")
    stats.update_max_abs("H", H_q)
    stats.update_max_abs("y", y_q)

    nt = H.shape[1]
    G_q = np.zeros((nt, nt), dtype=np.complex128)
    b_q = np.zeros(nt, dtype=np.complex128)

    for i in range(nt):
        h_i_conj = np.conj(H_q[:, i])
        for j in range(nt):
            products = fixed_mul_complex(
                h_i_conj, H_q[:, j], FMT_ACC, stats=stats, block="gram_matrix"
            )
            acc = quantize_with_format(
                np.sum(products), FMT_ACC, stats=stats, block="gram_matrix"
            )
            G_q[i, j] = quantize_with_format(acc, FMT_G, stats=stats, block="gram_matrix")

        products = fixed_mul_complex(
            h_i_conj, y_q, FMT_ACC, stats=stats, block="matched_filter"
        )
        acc = quantize_with_format(
            np.sum(products), FMT_ACC, stats=stats, block="matched_filter"
        )
        b_q[i] = quantize_with_format(acc, FMT_B, stats=stats, block="matched_filter")

    W_q = quantize_with_format(G_q, FMT_W, stats=stats, block="W_regularization")
    noise_q = quantize_real(noise_var, FMT_W, stats=stats, block="W_regularization")
    for i in range(nt):
        W_q[i, i] = fixed_add(
            W_q[i, i], noise_q, FMT_W, stats=stats, block="W_regularization"
        )

    stats.update_max_abs("G", G_q)
    stats.update_max_abs("b", b_q)
    stats.update_max_abs("W", W_q)
    return H_q, y_q, G_q, b_q, W_q


def safe_denominator(denominator, eps=1e-12):
    if np.abs(denominator) < eps:
        return eps + 0j
    return denominator


def fixed_divide_complex(numerator, denominator, stats):
    x = numerator / safe_denominator(denominator)
    return quantize_with_format(x, FMT_X, stats=stats, block="gs_update")


def fixed_gs_initial_guess(W, b, stats):
    x = np.zeros_like(b, dtype=np.complex128)
    for i in range(b.size):
        x[i] = fixed_divide_complex(b[i], W[i, i], stats)
    return x


def fixed_gs_detector_from_matrices(W, b, stats, iter_counts=GS_ITERS):
    nt = b.size
    x = fixed_gs_initial_guess(W, b, stats)
    requested = set(iter_counts)
    outputs = {}

    for iter_idx in range(1, max(requested) + 1):
        x_old = x.copy()
        for i in range(nt):
            if i > 0:
                lower_products = fixed_mul_complex(
                    W[i, :i], x[:i], FMT_ACC, stats=stats, block="gs_mac"
                )
                sum_lower = quantize_with_format(
                    np.sum(lower_products), FMT_ACC, stats=stats, block="gs_mac"
                )
            else:
                sum_lower = 0.0 + 0.0j

            if i + 1 < nt:
                upper_products = fixed_mul_complex(
                    W[i, i + 1 :], x_old[i + 1 :], FMT_ACC, stats=stats, block="gs_mac"
                )
                sum_upper = quantize_with_format(
                    np.sum(upper_products), FMT_ACC, stats=stats, block="gs_mac"
                )
            else:
                sum_upper = 0.0 + 0.0j

            numerator = b[i] - sum_lower - sum_upper
            numerator = quantize_with_format(
                numerator, FMT_ACC, stats=stats, block="gs_update"
            )
            x[i] = fixed_divide_complex(numerator, W[i, i], stats)

        if iter_idx in requested:
            x_out = quantize_with_format(x, FMT_X_OUT, stats=stats, block="gs_update")
            stats.update_max_abs("x_hat", x_out)
            stats.record_nan_inf(x_out)
            outputs[iter_idx] = x_out.copy()
    return outputs


def new_error_trackers():
    return {
        "G": ErrorAccumulator(),
        "b": ErrorAccumulator(),
        "W": ErrorAccumulator(),
        "x_gs16": ErrorAccumulator(),
    }


def simulate_snr(config, rng, snr_db, num_frames):
    bit_errors = {
        "MMSE_float": 0,
        "GS16_float": 0,
        "Adaptive_float": 0,
        "GS16_fixed": 0,
        "Adaptive_fixed": 0,
    }
    total_bits = 0
    float_mode_counts = {0: 0, 1: 0, 2: 0}
    fixed_mode_counts = {0: 0, 1: 0, 2: 0}
    mode_mismatch_count = 0
    fixed_ratio_rtl_mismatch_count = 0
    stats = FixedStats()
    error_trackers = new_error_trackers()
    float_condition = MetricAccumulator()
    fixed_condition = MetricAccumulator()

    for _ in range(num_frames):
        bits_tx = rng.integers(0, 2, size=2 * config.nt, dtype=np.int8)
        x = qpsk_mod(bits_tx)
        H = generate_channel(rng, nr=config.nr, nt=config.nt)
        y, noise_var = add_awgn(rng, H @ x, snr_db)

        G_float, b_float, W_float = float_reference_matrices(H, y, noise_var)
        x_mmse = np.linalg.solve(W_float, b_float)
        gs_float = gs_detector_from_matrices(W_float, b_float, iter_counts=GS_ITERS)

        float_metric = channel_condition_metric_from_G(G_float)
        float_condition.update(float_metric)
        float_mode = select_adaptive_mode_aggressive(snr_db, float_metric["dominance"])
        x_adaptive_float = gs_float[ADAPTIVE_MODE_ITERS[float_mode]]
        float_mode_counts[float_mode] += 1

        _, _, G_fixed, b_fixed, W_fixed = fixed_prepare_matrices(H, y, noise_var, stats)
        fixed_metric = channel_condition_metric_from_G(G_fixed)
        fixed_condition.update(fixed_metric)
        fixed_ratio_mode = select_adaptive_mode_aggressive(
            snr_db, fixed_metric["dominance"]
        )
        fixed_rtl_mode = select_adaptive_mode_aggressive_rtl_friendly(
            snr_db, fixed_metric["diag_sum"], fixed_metric["offdiag_sum"]
        )
        if fixed_ratio_mode != fixed_rtl_mode:
            fixed_ratio_rtl_mismatch_count += 1

        gs_fixed = fixed_gs_detector_from_matrices(
            W_fixed, b_fixed, stats, iter_counts=GS_ITERS
        )
        fixed_mode_counts[fixed_rtl_mode] += 1
        if fixed_rtl_mode != float_mode:
            mode_mismatch_count += 1

        error_trackers["G"].update(G_fixed, G_float)
        error_trackers["b"].update(b_fixed, b_float)
        error_trackers["W"].update(W_fixed, W_float)
        error_trackers["x_gs16"].update(gs_fixed[16], gs_float[16])

        x_adaptive_fixed = gs_fixed[ADAPTIVE_MODE_ITERS[fixed_rtl_mode]]
        detected = {
            "MMSE_float": qpsk_to_bits(x_mmse),
            "GS16_float": qpsk_to_bits(gs_float[16]),
            "Adaptive_float": qpsk_to_bits(x_adaptive_float),
            "GS16_fixed": qpsk_to_bits(gs_fixed[16]),
            "Adaptive_fixed": qpsk_to_bits(x_adaptive_fixed),
        }

        for name, bits_rx in detected.items():
            bit_errors[name] += np.count_nonzero(bits_tx != bits_rx)
        total_bits += bits_tx.size

    ber = {name: errors / total_bits for name, errors in bit_errors.items()}
    fixed_avg_iters = sum(
        count * ADAPTIVE_MODE_ITERS[mode] for mode, count in fixed_mode_counts.items()
    ) / num_frames
    float_avg_iters = sum(
        count * ADAPTIVE_MODE_ITERS[mode] for mode, count in float_mode_counts.items()
    ) / num_frames

    mode_summary = {
        "float_avg_iters": float_avg_iters,
        "fixed_avg_iters": fixed_avg_iters,
        "float_mode_fraction": {
            mode: count / num_frames for mode, count in float_mode_counts.items()
        },
        "fixed_mode_fraction": {
            mode: count / num_frames for mode, count in fixed_mode_counts.items()
        },
        "mode_mismatch_rate": mode_mismatch_count / num_frames,
        "fixed_ratio_rtl_mismatch_rate": fixed_ratio_rtl_mismatch_count / num_frames,
    }
    error_summary = {
        name: {"avg_abs": tracker.avg_abs(), "rms": tracker.rms()}
        for name, tracker in error_trackers.items()
    }
    condition_summary = {
        "float": float_condition.averages(),
        "fixed": fixed_condition.averages(),
    }
    return ber, mode_summary, stats, error_summary, condition_summary


def simulate_config(config, num_frames, seed):
    rng = np.random.default_rng(seed)
    results = {
        "config": config,
        "ber": {
            "MMSE_float": [],
            "GS16_float": [],
            "Adaptive_float": [],
            "GS16_fixed": [],
            "Adaptive_fixed": [],
        },
        "mode": {
            "float_avg_iters": [],
            "fixed_avg_iters": [],
            "mode_mismatch_rate": [],
            "fixed_ratio_rtl_mismatch_rate": [],
            "float_mode_fraction": {0: [], 1: [], 2: []},
            "fixed_mode_fraction": {0: [], 1: [], 2: []},
        },
        "stats": [],
        "errors": [],
        "condition": {"float": [], "fixed": []},
    }

    for snr_db in SNR_DB_LIST:
        ber, mode_summary, stats, error_summary, condition_summary = simulate_snr(
            config, rng, snr_db, num_frames
        )
        for name in results["ber"]:
            results["ber"][name].append(ber[name])

        results["mode"]["float_avg_iters"].append(mode_summary["float_avg_iters"])
        results["mode"]["fixed_avg_iters"].append(mode_summary["fixed_avg_iters"])
        results["mode"]["mode_mismatch_rate"].append(mode_summary["mode_mismatch_rate"])
        results["mode"]["fixed_ratio_rtl_mismatch_rate"].append(
            mode_summary["fixed_ratio_rtl_mismatch_rate"]
        )
        for mode in (0, 1, 2):
            results["mode"]["float_mode_fraction"][mode].append(
                mode_summary["float_mode_fraction"][mode]
            )
            results["mode"]["fixed_mode_fraction"][mode].append(
                mode_summary["fixed_mode_fraction"][mode]
            )

        results["stats"].append(stats)
        results["errors"].append(error_summary)
        results["condition"]["float"].append(condition_summary["float"])
        results["condition"]["fixed"].append(condition_summary["fixed"])
    return results


def mean_curve_gap(ber, lhs, rhs):
    return float(np.mean(np.asarray(ber[lhs]) - np.asarray(ber[rhs])))


def total_saturation(results):
    return sum(stats.saturation_count for stats in results["stats"])


def total_nan_inf(results):
    return sum(stats.nan_inf_count for stats in results["stats"])


def average_error(results, name, metric):
    return float(np.mean([err[name][metric] for err in results["errors"]]))


def average_condition(results, domain, name):
    return float(np.mean([entry[name] for entry in results["condition"][domain]]))


def compute_metrics(results, num_frames):
    ber = results["ber"]
    mode = results["mode"]
    total_frames = num_frames * len(SNR_DB_LIST)
    fixed_avg_iters = float(np.mean(mode["fixed_avg_iters"]))
    mode_fractions = {
        m: float(np.mean(mode["fixed_mode_fraction"][m])) for m in (0, 1, 2)
    }
    return {
        "adaptive_fixed_avg_ber": float(np.mean(ber["Adaptive_fixed"])),
        "adaptive_gap": mean_curve_gap(ber, "Adaptive_fixed", "Adaptive_float"),
        "gs16_gap": mean_curve_gap(ber, "GS16_fixed", "GS16_float"),
        "adaptive_vs_gs16_fixed": mean_curve_gap(ber, "Adaptive_fixed", "GS16_fixed"),
        "fixed_avg_iters": fixed_avg_iters,
        "saving_vs_gs16": 100.0 * (1.0 - fixed_avg_iters / 16.0),
        "mode_mismatch_rate": float(np.mean(mode["mode_mismatch_rate"])),
        "fixed_ratio_rtl_mismatch_rate": float(
            np.mean(mode["fixed_ratio_rtl_mismatch_rate"])
        ),
        "mode_fractions": mode_fractions,
        "saturation_count": total_saturation(results),
        "nan_inf_count": total_nan_inf(results),
        "avg_saturation_per_frame": total_saturation(results) / total_frames,
    }


def run_checks(results, num_frames):
    metrics = compute_metrics(results, num_frames)
    checks = {
        "fixed BER does not become random": metrics["adaptive_fixed_avg_ber"] < 0.25,
        "fixed GS16 close to float GS16": abs(metrics["gs16_gap"]) < 3e-3,
        "adaptive fixed close to adaptive float": abs(metrics["adaptive_gap"]) < 3e-3,
        "mode mismatch below 1%": metrics["mode_mismatch_rate"] < 0.01,
        "no NaN/Inf": metrics["nan_inf_count"] == 0,
        "saturation not excessive": metrics["avg_saturation_per_frame"] < 1.0,
    }
    return checks


def config_status(checks, metrics):
    if all(checks.values()) and metrics["saturation_count"] == 0:
        return "PASS"
    if (
        checks["fixed BER does not become random"]
        and checks["fixed GS16 close to float GS16"]
        and checks["adaptive fixed close to adaptive float"]
        and checks["mode mismatch below 1%"]
        and checks["no NaN/Inf"]
        and checks["saturation not excessive"]
    ):
        return "WATCH"
    return "RETUNE"


def print_ber_table(results):
    config = results["config"]
    ber = results["ber"]
    print()
    print(f"BER table: {config.name}")
    print(
        f"{'SNR':>5} {'MMSE_float':>12} {'GS16_float':>12} "
        f"{'Adaptive_float':>15} {'GS16_fixed':>12} {'Adaptive_fixed':>15}"
    )
    for idx, snr_db in enumerate(SNR_DB_LIST):
        print(
            f"{snr_db:5d} "
            f"{ber['MMSE_float'][idx]:12.5e} "
            f"{ber['GS16_float'][idx]:12.5e} "
            f"{ber['Adaptive_float'][idx]:15.5e} "
            f"{ber['GS16_fixed'][idx]:12.5e} "
            f"{ber['Adaptive_fixed'][idx]:15.5e}"
        )


def print_summary(results, num_frames):
    config = results["config"]
    metrics = compute_metrics(results, num_frames)
    print()
    print(f"Summary: {config.name}")
    print(f"- average Adaptive_fixed BER: {metrics['adaptive_fixed_avg_ber']:.5e}")
    print(
        "- average Adaptive_fixed gap vs Adaptive_float: "
        f"{metrics['adaptive_gap']:.5e}"
    )
    print(
        "- average GS16_fixed gap vs GS16_float: "
        f"{metrics['gs16_gap']:.5e}"
    )
    print(
        "- average Adaptive_fixed gap vs GS16_fixed: "
        f"{metrics['adaptive_vs_gs16_fixed']:.5e}"
    )
    print(f"- fixed adaptive average iterations: {metrics['fixed_avg_iters']:.3f}")
    print(f"- saving vs fixed GS16: {metrics['saving_vs_gs16']:.2f}%")
    print(f"- mode mismatch rate: {metrics['mode_mismatch_rate']:.5f}")
    print(f"- fixed ratio vs RTL-style mismatch: {metrics['fixed_ratio_rtl_mismatch_rate']:.5f}")
    print(f"- total saturation count: {metrics['saturation_count']}")
    print(f"- total NaN/Inf count: {metrics['nan_inf_count']}")


def print_mode_distribution(results):
    config = results["config"]
    metrics = compute_metrics(results, num_frames=1)
    fractions = metrics["mode_fractions"]
    print()
    print(f"Mode distribution: {config.name}")
    print(f"- GS-4 fraction:  {fractions[0]:.4f}")
    print(f"- GS-8 fraction:  {fractions[1]:.4f}")
    print(f"- GS-16 fraction: {fractions[2]:.4f}")


def print_quantization_error_summary(results):
    config = results["config"]
    print()
    print(f"Quantization error summary: {config.name}")
    print(f"{'Signal':>8} {'avg abs':>12} {'rms':>12}")
    for name in ("G", "b", "W", "x_gs16"):
        print(
            f"{name:>8} "
            f"{average_error(results, name, 'avg_abs'):12.5e} "
            f"{average_error(results, name, 'rms'):12.5e}"
        )


def print_condition_summary(results):
    config = results["config"]
    print()
    print(f"Condition metric summary: {config.name}")
    print(
        f"{'Metric':>8} {'float':>12} {'fixed':>12}"
    )
    for name in ("diag_sum", "offdiag_sum", "dominance"):
        print(
            f"{name:>8} "
            f"{average_condition(results, 'float', name):12.5e} "
            f"{average_condition(results, 'fixed', name):12.5e}"
        )


def print_checks(results, num_frames):
    config = results["config"]
    metrics = compute_metrics(results, num_frames)
    checks = run_checks(results, num_frames)
    status = config_status(checks, metrics)
    print()
    print(f"Correctness checks: {config.name} ({status})")
    for label, passed in checks.items():
        print(f"- {label}: {'PASS' if passed else 'FAIL'}")
    if metrics["saturation_count"] > 0:
        print("- saturation note: nonzero saturation observed; inspect scaling plot.")
    return checks, status


def plot_ber_scaling(all_results):
    plt.figure(figsize=(10, 6))
    for results in all_results:
        config = results["config"]
        plt.semilogy(
            SNR_DB_LIST,
            results["ber"]["Adaptive_fixed"],
            marker="o",
            linewidth=1.8,
            label=f"{config.name} Adaptive_fixed",
        )
        plt.semilogy(
            SNR_DB_LIST,
            results["ber"]["MMSE_float"],
            marker=".",
            linestyle="--",
            linewidth=1.2,
            label=f"{config.name} MMSE_float",
        )
    plt.grid(True, which="both", linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("BER")
    plt.title("Phase 4 Fixed-Point Scaling BER")
    plt.legend(fontsize=8)
    plt.tight_layout()
    output_path = OUTPUT_DIR / "phase4_ber_scaling_fixed_4x4_8x4_8x8.png"
    plt.savefig(output_path, dpi=300)
    plt.close()
    print(f"Saved BER scaling plot: {output_path}")


def plot_avg_iters_scaling(all_results):
    plt.figure(figsize=(9, 5))
    for results in all_results:
        config = results["config"]
        plt.plot(
            SNR_DB_LIST,
            results["mode"]["fixed_avg_iters"],
            marker="o",
            linewidth=1.8,
            label=config.name,
        )
    plt.axhline(16, linestyle="--", linewidth=1.1, label="Fixed GS-16")
    plt.grid(True, linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("Average adaptive fixed iterations")
    plt.title("Phase 4 Adaptive Iteration Scaling")
    plt.legend()
    plt.tight_layout()
    output_path = OUTPUT_DIR / "phase4_avg_iters_scaling.png"
    plt.savefig(output_path, dpi=300)
    plt.close()
    print(f"Saved average-iterations scaling plot: {output_path}")


def plot_mode_distribution_scaling(all_results):
    labels = [results["config"].name for results in all_results]
    x = np.arange(len(labels))
    fractions = []
    for results in all_results:
        mode = results["mode"]["fixed_mode_fraction"]
        fractions.append([float(np.mean(mode[m])) for m in (0, 1, 2)])
    fractions = np.asarray(fractions)

    plt.figure(figsize=(8, 5))
    bottom = np.zeros(len(labels))
    for idx, label in enumerate(("GS-4", "GS-8", "GS-16")):
        plt.bar(x, fractions[:, idx], bottom=bottom, label=label)
        bottom += fractions[:, idx]
    plt.xticks(x, labels)
    plt.ylim(0, 1.0)
    plt.ylabel("Average mode fraction")
    plt.title("Phase 4 Average Mode Distribution")
    plt.legend()
    plt.grid(True, axis="y", linestyle=":")
    plt.tight_layout()
    output_path = OUTPUT_DIR / "phase4_mode_distribution_scaling.png"
    plt.savefig(output_path, dpi=300)
    plt.close()
    print(f"Saved mode-distribution scaling plot: {output_path}")


def plot_saturation_scaling(all_results):
    plt.figure(figsize=(9, 5))
    for results in all_results:
        config = results["config"]
        sat = [stats.saturation_count for stats in results["stats"]]
        plt.plot(SNR_DB_LIST, sat, marker="o", linewidth=1.8, label=config.name)
    plt.grid(True, linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("Saturation count")
    plt.title("Phase 4 Saturation Scaling")
    plt.legend()
    plt.tight_layout()
    output_path = OUTPUT_DIR / "phase4_saturation_scaling.png"
    plt.savefig(output_path, dpi=300)
    plt.close()
    print(f"Saved saturation scaling plot: {output_path}")


def plot_fixed_float_gap_scaling(all_results):
    plt.figure(figsize=(9, 5))
    for results in all_results:
        config = results["config"]
        gap = np.asarray(results["ber"]["Adaptive_fixed"]) - np.asarray(
            results["ber"]["Adaptive_float"]
        )
        plt.plot(SNR_DB_LIST, gap, marker="o", linewidth=1.8, label=config.name)
    plt.axhline(0.0, color="k", linewidth=1.0)
    plt.grid(True, linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("Adaptive fixed - Adaptive float BER")
    plt.title("Phase 4 Fixed-vs-Float Adaptive BER Gap")
    plt.legend()
    plt.tight_layout()
    output_path = OUTPUT_DIR / "phase4_fixed_float_gap_scaling.png"
    plt.savefig(output_path, dpi=300)
    plt.close()
    print(f"Saved fixed-float gap scaling plot: {output_path}")


def make_plots(all_results):
    plot_ber_scaling(all_results)
    plot_avg_iters_scaling(all_results)
    plot_mode_distribution_scaling(all_results)
    plot_saturation_scaling(all_results)
    plot_fixed_float_gap_scaling(all_results)


def print_phase4_decision(all_results, num_frames, status_by_config):
    statuses = {name: status for name, status in status_by_config.items()}
    metrics_by_config = {
        results["config"].name: compute_metrics(results, num_frames)
        for results in all_results
    }
    all_close = all(
        abs(metrics["adaptive_gap"]) < 3e-3
        and abs(metrics["gs16_gap"]) < 3e-3
        and metrics["mode_mismatch_rate"] < 0.01
        for metrics in metrics_by_config.values()
    )
    any_saturation = any(metrics["saturation_count"] > 0 for metrics in metrics_by_config.values())
    any_retune = any(status == "RETUNE" for status in statuses.values())
    best_ber = min(
        metrics_by_config,
        key=lambda name: metrics_by_config[name]["adaptive_fixed_avg_ber"],
    )
    rtl_choice = "4x4" if "4x4" in metrics_by_config else next(iter(metrics_by_config))
    if "8x4" in metrics_by_config and statuses.get("8x4") != "RETUNE":
        report_choice = "8x4"
    else:
        report_choice = best_ber

    print()
    print("PHASE 4 SCALING DECISION:")
    for name in ("4x4", "8x4", "8x8"):
        if name in statuses:
            print(f"- {name} status: {statuses[name]}")
        else:
            print(f"- {name} status: not run")
    print(
        "- Does adaptive GS generalize? "
        f"{'YES' if all_close and not any_retune else 'PARTIAL'}"
    )
    print(f"- Which configuration is best for RTL? {rtl_choice}")
    print(f"- Which configuration is best for report scaling evidence? {report_choice}")
    if any_saturation:
        print("- Any Q-format changes needed? maybe for saturated configs; inspect counts.")
    elif any_retune:
        print("- Any Q-format changes needed? likely, for at least one retune config.")
    else:
        print("- Any Q-format changes needed? none indicated by this run.")
    if any_retune or any_saturation:
        print("- Recommended next step: tune wider input/accumulation formats or run focused validation.")
    else:
        print("- Recommended next step: proceed to Phase 4 report write-up and Phase 5 RTL planning.")


def parse_configs(config_arg):
    available = {entry["name"]: MimoConfig(**entry) for entry in CONFIGS}
    if not config_arg:
        return list(available.values())
    requested = [item.strip() for item in config_arg.split(",") if item.strip()]
    unknown = [name for name in requested if name not in available]
    if unknown:
        valid = ", ".join(available)
        raise SystemExit(f"Unknown config(s): {', '.join(unknown)}. Valid configs: {valid}")
    return [available[name] for name in requested]


def resolve_frames(args):
    if args.num_frames is not None:
        return args.num_frames, "CUSTOM"
    if args.validate:
        return VALIDATE_FRAMES, "VALIDATE"
    return QUICK_FRAMES, "QUICK"


def parse_args():
    parser = ArgumentParser(description="Phase 4 fixed-point MIMO scaling study")
    parser.add_argument("--quick", action="store_true", help="Use 1000 frames per SNR")
    parser.add_argument("--validate", action="store_true", help="Use 3000 frames per SNR")
    parser.add_argument("--num-frames", type=int, default=None, help="Custom frames per SNR")
    parser.add_argument(
        "--configs",
        default="4x4,8x4,8x8",
        help="Comma-separated config list, e.g. 4x4,8x4,8x8",
    )
    parser.add_argument("--seed", type=int, default=RNG_SEED)
    return parser.parse_args()


def main():
    args = parse_args()
    configs = parse_configs(args.configs)
    num_frames, run_label = resolve_frames(args)

    print("Phase 4 fixed-point scaling study")
    print(f"Run mode: {run_label}")
    print(f"Frames/SNR = {num_frames}, seed = {args.seed}")
    print(f"SNR points: {SNR_DB_LIST}")
    print("Fixed formats: H/y=Q4.12, G/b/W=Q8.12, ACC=Q12.16, x=Q6.16, x_out=Q4.12")
    print("Reciprocal mode: exact")
    print("Policy: aggressive, fixed selector uses RTL-friendly cross multiply")
    print()

    all_results = []
    status_by_config = {}
    for idx, config in enumerate(configs):
        print(f"Running config {config.name}: NR={config.nr}, NT={config.nt}")
        results = simulate_config(config, num_frames=num_frames, seed=args.seed + 1000 * idx)
        all_results.append(results)
        print_ber_table(results)
        print_summary(results, num_frames)
        print_mode_distribution(results)
        print_quantization_error_summary(results)
        print_condition_summary(results)
        _, status = print_checks(results, num_frames)
        status_by_config[config.name] = status
        print()

    make_plots(all_results)
    print_phase4_decision(all_results, num_frames, status_by_config)


if __name__ == "__main__":
    main()
