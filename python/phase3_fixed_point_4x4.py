from argparse import ArgumentParser
from dataclasses import dataclass, field
from pathlib import Path
import json

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt


NT = 4
NR = 4
NUM_FRAMES = 20_000
QUICK_FRAMES = 2_000
VALIDATE_FRAMES = 5_000
SNR_DB_LIST = list(range(0, 22, 2))
RNG_SEED = 42
GS_ITERS = (4, 8, 16)
ADAPTIVE_MODE_ITERS = {0: 4, 1: 8, 2: 16}
OUTPUT_DIR = Path(__file__).resolve().parents[1]


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

    @property
    def min_value(self):
        return self.int_min / self.scale

    @property
    def max_value(self):
        return self.int_max / self.scale


@dataclass(frozen=True)
class FormatProfile:
    name: str
    H: FixedFormat
    Y: FixedFormat
    G: FixedFormat
    B: FixedFormat
    W: FixedFormat
    ACC: FixedFormat
    X: FixedFormat
    X_OUT: FixedFormat


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


FORMAT_PROFILES = {
    "safe_current": FormatProfile(
        "safe_current",
        H=FixedFormat("Q4.12", 16, 12),
        Y=FixedFormat("Q4.12", 16, 12),
        G=FixedFormat("Q8.12", 20, 12),
        B=FixedFormat("Q8.12", 20, 12),
        W=FixedFormat("Q8.12", 20, 12),
        ACC=FixedFormat("Q12.16", 28, 16),
        X=FixedFormat("Q6.16", 22, 16),
        X_OUT=FixedFormat("Q4.12", 16, 12),
    ),
    "medium": FormatProfile(
        "medium",
        H=FixedFormat("Q3.11", 14, 11),
        Y=FixedFormat("Q3.11", 14, 11),
        G=FixedFormat("Q7.11", 18, 11),
        B=FixedFormat("Q7.11", 18, 11),
        W=FixedFormat("Q7.11", 18, 11),
        ACC=FixedFormat("Q10.14", 24, 14),
        X=FixedFormat("Q5.14", 20, 14),
        X_OUT=FixedFormat("Q3.11", 14, 11),
    ),
    "aggressive_narrow": FormatProfile(
        "aggressive_narrow",
        H=FixedFormat("Q3.10", 13, 10),
        Y=FixedFormat("Q3.10", 13, 10),
        G=FixedFormat("Q7.10", 17, 10),
        B=FixedFormat("Q7.10", 17, 10),
        W=FixedFormat("Q7.10", 17, 10),
        ACC=FixedFormat("Q9.13", 22, 13),
        X=FixedFormat("Q5.13", 19, 13),
        X_OUT=FixedFormat("Q3.10", 13, 10),
    ),
    "accumulator_only_narrow": FormatProfile(
        "accumulator_only_narrow",
        H=FixedFormat("Q4.12", 16, 12),
        Y=FixedFormat("Q4.12", 16, 12),
        G=FixedFormat("Q8.12", 20, 12),
        B=FixedFormat("Q8.12", 20, 12),
        W=FixedFormat("Q8.12", 20, 12),
        ACC=FixedFormat("Q10.14", 24, 14),
        X=FixedFormat("Q6.16", 22, 16),
        X_OUT=FixedFormat("Q4.12", 16, 12),
    ),
}

RECIPROCAL_FORMATS = {
    "quantized": FixedFormat("Q4.20", 24, 20),
    "coarse_lut": FixedFormat("Q4.14", 18, 14),
}

ACTIVE_PROFILE = None
FMT_H = FMT_Y = FMT_G = FMT_B = FMT_W = FMT_ACC = FMT_X = FMT_X_OUT = None


def set_active_profile(profile_name):
    global ACTIVE_PROFILE, FMT_H, FMT_Y, FMT_G, FMT_B, FMT_W, FMT_ACC, FMT_X, FMT_X_OUT
    ACTIVE_PROFILE = FORMAT_PROFILES[profile_name]
    FMT_H = ACTIVE_PROFILE.H
    FMT_Y = ACTIVE_PROFILE.Y
    FMT_G = ACTIVE_PROFILE.G
    FMT_B = ACTIVE_PROFILE.B
    FMT_W = ACTIVE_PROFILE.W
    FMT_ACC = ACTIVE_PROFILE.ACC
    FMT_X = ACTIVE_PROFILE.X
    FMT_X_OUT = ACTIVE_PROFILE.X_OUT


set_active_profile("safe_current")


def quantize_real(value, total_bits, frac_bits, saturate=True, stats=None, block="quant"):
    scale = 2**frac_bits
    int_min = -(2 ** (total_bits - 1))
    int_max = 2 ** (total_bits - 1) - 1
    arr = np.asarray(value, dtype=np.float64)
    raw = np.round(arr * scale)
    overflow = (raw < int_min) | (raw > int_max)
    overflow_count = int(np.count_nonzero(overflow))

    if stats is not None:
        stats.record_saturation(block, overflow_count)

    if saturate:
        raw = np.clip(raw, int_min, int_max)

    quantized = raw / scale
    if np.ndim(value) == 0:
        return float(quantized)
    return quantized


def quantize_complex(value, total_bits, frac_bits, saturate=True, stats=None, block="quant"):
    real = quantize_real(
        np.real(value), total_bits, frac_bits, saturate=saturate, stats=stats, block=block
    )
    imag = quantize_real(
        np.imag(value), total_bits, frac_bits, saturate=saturate, stats=stats, block=block
    )
    return real + 1j * imag


def quantize_with_format(value, fmt, stats=None, block="quant"):
    if np.iscomplexobj(value):
        return quantize_complex(
            value, fmt.total_bits, fmt.frac_bits, stats=stats, block=block
        )
    return quantize_real(value, fmt.total_bits, fmt.frac_bits, stats=stats, block=block)


def fixed_to_int(value, fmt):
    real = np.round(np.real(value) * fmt.scale).astype(np.int64)
    if np.iscomplexobj(value):
        imag = np.round(np.imag(value) * fmt.scale).astype(np.int64)
        return real, imag
    return real


def fixed_add(a, b, fmt, stats=None, block="add"):
    return quantize_with_format(a + b, fmt, stats=stats, block=block)


def fixed_mul_real(a, b, fmt, stats=None, block="mul_real"):
    return quantize_real(a * b, fmt.total_bits, fmt.frac_bits, stats=stats, block=block)


def fixed_mul_complex(a, b, fmt, stats=None, block="mul_complex"):
    product = (np.real(a) * np.real(b) - np.imag(a) * np.imag(b)) + 1j * (
        np.real(a) * np.imag(b) + np.imag(a) * np.real(b)
    )
    return quantize_complex(
        product, fmt.total_bits, fmt.frac_bits, stats=stats, block=block
    )


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


def generate_channel(rng, n_rx=NR, n_tx=NT):
    return (
        rng.standard_normal((n_rx, n_tx))
        + 1j * rng.standard_normal((n_rx, n_tx))
    ) / np.sqrt(2)


def add_awgn(rng, signal, snr_db):
    snr_linear = 10 ** (snr_db / 10)
    noise_var = 1 / snr_linear
    noise = np.sqrt(noise_var / 2) * (
        rng.standard_normal(signal.shape) + 1j * rng.standard_normal(signal.shape)
    )
    return signal + noise, noise_var


def mmse_detector(H, y, noise_var):
    n_tx = H.shape[1]
    G = H.conj().T @ H
    b = H.conj().T @ y
    W = G + noise_var * np.eye(n_tx, dtype=np.complex128)
    return np.linalg.solve(W, b)


def gs_detector_at_iters(H, y, noise_var, iter_counts=GS_ITERS):
    n_tx = H.shape[1]
    G = H.conj().T @ H
    b = H.conj().T @ y
    W = G + noise_var * np.eye(n_tx, dtype=np.complex128)
    x = b / np.diag(W)

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


def float_reference_matrices(H, y, noise_var):
    G = H.conj().T @ H
    b = H.conj().T @ y
    W = G + noise_var * np.eye(H.shape[1], dtype=np.complex128)
    return G, b, W


def fixed_prepare_matrices(H, y, noise_var, stats):
    H_q = quantize_with_format(H, FMT_H, stats=stats, block="input_quant")
    y_q = quantize_with_format(y, FMT_Y, stats=stats, block="input_quant")
    stats.update_max_abs("H", H_q)
    stats.update_max_abs("y", y_q)

    n_tx = H.shape[1]
    G_q = np.zeros((n_tx, n_tx), dtype=np.complex128)
    b_q = np.zeros(n_tx, dtype=np.complex128)

    for i in range(n_tx):
        for j in range(n_tx):
            products = fixed_mul_complex(
                np.conj(H_q[:, i]), H_q[:, j], FMT_ACC, stats=stats, block="gram_matrix"
            )
            acc = quantize_with_format(
                np.sum(products), FMT_ACC, stats=stats, block="gram_matrix"
            )
            G_q[i, j] = quantize_with_format(
                acc, FMT_G, stats=stats, block="gram_matrix"
            )

        products = fixed_mul_complex(
            np.conj(H_q[:, i]), y_q, FMT_ACC, stats=stats, block="matched_filter"
        )
        acc = quantize_with_format(
            np.sum(products), FMT_ACC, stats=stats, block="matched_filter"
        )
        b_q[i] = quantize_with_format(acc, FMT_B, stats=stats, block="matched_filter")

    W_q = quantize_with_format(G_q, FMT_W, stats=stats, block="W_regularization")
    noise_q = quantize_real(
        noise_var, FMT_W.total_bits, FMT_W.frac_bits, stats=stats, block="W_regularization"
    )
    for i in range(n_tx):
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


def fixed_divide_complex(numerator, denominator, stats, reciprocal_mode):
    denominator = safe_denominator(denominator)
    if reciprocal_mode == "exact":
        x = numerator / denominator
        return quantize_with_format(x, FMT_X, stats=stats, block="gs_update")

    recip_fmt = RECIPROCAL_FORMATS[reciprocal_mode]
    reciprocal = quantize_with_format(
        1 / denominator, recip_fmt, stats=stats, block="reciprocal"
    )
    x = fixed_mul_complex(numerator, reciprocal, FMT_X, stats=stats, block="gs_update")
    return quantize_with_format(x, FMT_X, stats=stats, block="gs_update")


def fixed_gs_initial_guess(W, b, stats, reciprocal_mode):
    x = np.zeros_like(b, dtype=np.complex128)
    for i in range(b.size):
        x[i] = fixed_divide_complex(b[i], W[i, i], stats, reciprocal_mode)
    return x


def fixed_gs_detector_at_iters(W, b, stats, iter_counts=GS_ITERS, reciprocal_mode="exact"):
    n_tx = b.size
    x = fixed_gs_initial_guess(W, b, stats, reciprocal_mode)
    requested = set(iter_counts)
    outputs = {}

    for iter_idx in range(1, max(requested) + 1):
        x_old = x.copy()
        for i in range(n_tx):
            if i > 0:
                lower_products = fixed_mul_complex(
                    W[i, :i], x[:i], FMT_ACC, stats=stats, block="gs_mac"
                )
                sum_lower = quantize_with_format(
                    np.sum(lower_products), FMT_ACC, stats=stats, block="gs_mac"
                )
            else:
                sum_lower = 0.0 + 0.0j

            if i + 1 < n_tx:
                upper_products = fixed_mul_complex(
                    W[i, i + 1 :],
                    x_old[i + 1 :],
                    FMT_ACC,
                    stats=stats,
                    block="gs_mac",
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
            x[i] = fixed_divide_complex(numerator, W[i, i], stats, reciprocal_mode)

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


def simulate_snr(rng, snr_db, num_frames, reciprocal_mode="exact", store_examples=False):
    bit_errors = {
        "MMSE_float": 0,
        "GS4_float": 0,
        "GS8_float": 0,
        "GS16_float": 0,
        "Adaptive_float": 0,
        "GS4_fixed": 0,
        "GS8_fixed": 0,
        "GS16_fixed": 0,
        "Adaptive_fixed": 0,
    }
    total_bits = 0
    float_mode_counts = {0: 0, 1: 0, 2: 0}
    fixed_mode_counts = {0: 0, 1: 0, 2: 0}
    mode_mismatch_count = 0
    float_ratio_rtl_mismatch_count = 0
    fixed_ratio_rtl_mismatch_count = 0
    mismatch_examples = []
    stats = FixedStats()
    error_trackers = new_error_trackers()

    for _ in range(num_frames):
        bits_tx = rng.integers(0, 2, size=2 * NT, dtype=np.int8)
        x = qpsk_mod(bits_tx)

        H = generate_channel(rng, n_rx=NR, n_tx=NT)
        y_clean = H @ x
        y, noise_var = add_awgn(rng, y_clean, snr_db)

        G_float, b_float, W_float = float_reference_matrices(H, y, noise_var)
        x_mmse = mmse_detector(H, y, noise_var)
        gs_float = gs_detector_at_iters(H, y, noise_var, iter_counts=GS_ITERS)

        float_metric = channel_condition_metric_from_G(G_float)
        float_ratio_mode = select_adaptive_mode_aggressive(
            snr_db, float_metric["dominance"]
        )
        float_rtl_mode = select_adaptive_mode_aggressive_rtl_friendly(
            snr_db, float_metric["diag_sum"], float_metric["offdiag_sum"]
        )
        if float_ratio_mode != float_rtl_mode:
            float_ratio_rtl_mismatch_count += 1
            if store_examples and len(mismatch_examples) < 5:
                mismatch_examples.append(
                    {
                        "kind": "float_ratio_vs_rtl",
                        "snr_db": snr_db,
                        "ratio_mode": float_ratio_mode,
                        "rtl_mode": float_rtl_mode,
                        **float_metric,
                    }
                )

        float_adaptive_iters = ADAPTIVE_MODE_ITERS[float_ratio_mode]
        x_adaptive_float = gs_float[float_adaptive_iters]
        float_mode_counts[float_ratio_mode] += 1

        _, _, G_fixed, b_fixed, W_fixed = fixed_prepare_matrices(
            H, y, noise_var, stats
        )
        error_trackers["G"].update(G_fixed, G_float)
        error_trackers["b"].update(b_fixed, b_float)
        error_trackers["W"].update(W_fixed, W_float)

        gs_fixed = fixed_gs_detector_at_iters(
            W_fixed,
            b_fixed,
            stats,
            iter_counts=GS_ITERS,
            reciprocal_mode=reciprocal_mode,
        )
        error_trackers["x_gs16"].update(gs_fixed[16], gs_float[16])

        fixed_metric = channel_condition_metric_from_G(G_fixed)
        fixed_ratio_mode = select_adaptive_mode_aggressive(
            snr_db, fixed_metric["dominance"]
        )
        fixed_rtl_mode = select_adaptive_mode_aggressive_rtl_friendly(
            snr_db, fixed_metric["diag_sum"], fixed_metric["offdiag_sum"]
        )
        if fixed_ratio_mode != fixed_rtl_mode:
            fixed_ratio_rtl_mismatch_count += 1
            if store_examples and len(mismatch_examples) < 5:
                mismatch_examples.append(
                    {
                        "kind": "fixed_ratio_vs_rtl",
                        "snr_db": snr_db,
                        "ratio_mode": fixed_ratio_mode,
                        "rtl_mode": fixed_rtl_mode,
                        **fixed_metric,
                    }
                )

        fixed_adaptive_iters = ADAPTIVE_MODE_ITERS[fixed_rtl_mode]
        x_adaptive_fixed = gs_fixed[fixed_adaptive_iters]
        fixed_mode_counts[fixed_rtl_mode] += 1
        if fixed_rtl_mode != float_ratio_mode:
            mode_mismatch_count += 1

        detected = {
            "MMSE_float": qpsk_to_bits(x_mmse),
            "GS4_float": qpsk_to_bits(gs_float[4]),
            "GS8_float": qpsk_to_bits(gs_float[8]),
            "GS16_float": qpsk_to_bits(gs_float[16]),
            "Adaptive_float": qpsk_to_bits(x_adaptive_float),
            "GS4_fixed": qpsk_to_bits(gs_fixed[4]),
            "GS8_fixed": qpsk_to_bits(gs_fixed[8]),
            "GS16_fixed": qpsk_to_bits(gs_fixed[16]),
            "Adaptive_fixed": qpsk_to_bits(x_adaptive_fixed),
        }

        for name, bits_rx in detected.items():
            bit_errors[name] += np.count_nonzero(bits_tx != bits_rx)
        total_bits += bits_tx.size

    ber = {name: errors / total_bits for name, errors in bit_errors.items()}
    float_avg_iters = sum(
        count * ADAPTIVE_MODE_ITERS[mode] for mode, count in float_mode_counts.items()
    ) / num_frames
    fixed_avg_iters = sum(
        count * ADAPTIVE_MODE_ITERS[mode] for mode, count in fixed_mode_counts.items()
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
        "float_ratio_rtl_mismatch_rate": float_ratio_rtl_mismatch_count / num_frames,
        "fixed_ratio_rtl_mismatch_rate": fixed_ratio_rtl_mismatch_count / num_frames,
        "mismatch_examples": mismatch_examples,
    }

    error_summary = {
        name: {"avg_abs": tracker.avg_abs(), "rms": tracker.rms()}
        for name, tracker in error_trackers.items()
    }

    return ber, mode_summary, stats, error_summary


def simulate(num_frames, seed, reciprocal_mode="exact", store_examples=False):
    rng = np.random.default_rng(seed)
    results = {
        "profile": ACTIVE_PROFILE.name,
        "reciprocal_mode": reciprocal_mode,
        "ber": {
            "MMSE_float": [],
            "GS4_float": [],
            "GS8_float": [],
            "GS16_float": [],
            "Adaptive_float": [],
            "GS4_fixed": [],
            "GS8_fixed": [],
            "GS16_fixed": [],
            "Adaptive_fixed": [],
        },
        "mode": {
            "float_avg_iters": [],
            "fixed_avg_iters": [],
            "mode_mismatch_rate": [],
            "float_ratio_rtl_mismatch_rate": [],
            "fixed_ratio_rtl_mismatch_rate": [],
            "float_mode_fraction": {0: [], 1: [], 2: []},
            "fixed_mode_fraction": {0: [], 1: [], 2: []},
            "mismatch_examples": [],
        },
        "stats": [],
        "errors": [],
    }

    for snr_db in SNR_DB_LIST:
        ber, mode_summary, stats, error_summary = simulate_snr(
            rng,
            snr_db,
            num_frames,
            reciprocal_mode=reciprocal_mode,
            store_examples=store_examples,
        )
        for name, values in results["ber"].items():
            values.append(ber[name])

        results["mode"]["float_avg_iters"].append(mode_summary["float_avg_iters"])
        results["mode"]["fixed_avg_iters"].append(mode_summary["fixed_avg_iters"])
        results["mode"]["mode_mismatch_rate"].append(
            mode_summary["mode_mismatch_rate"]
        )
        results["mode"]["float_ratio_rtl_mismatch_rate"].append(
            mode_summary["float_ratio_rtl_mismatch_rate"]
        )
        results["mode"]["fixed_ratio_rtl_mismatch_rate"].append(
            mode_summary["fixed_ratio_rtl_mismatch_rate"]
        )
        results["mode"]["mismatch_examples"].extend(mode_summary["mismatch_examples"])
        for mode in (0, 1, 2):
            results["mode"]["float_mode_fraction"][mode].append(
                mode_summary["float_mode_fraction"][mode]
            )
            results["mode"]["fixed_mode_fraction"][mode].append(
                mode_summary["fixed_mode_fraction"][mode]
            )

        results["stats"].append(stats)
        results["errors"].append(error_summary)

    return results


def mean_curve_gap(ber, lhs, rhs):
    return float(np.mean(np.asarray(ber[lhs]) - np.asarray(ber[rhs])))


def total_saturation(results):
    return sum(stats.saturation_count for stats in results["stats"])


def total_nan_inf(results):
    return sum(stats.nan_inf_count for stats in results["stats"])


def compute_main_metrics(results):
    ber = results["ber"]
    mode = results["mode"]
    return {
        "adaptive_fixed_avg_ber": float(np.mean(ber["Adaptive_fixed"])),
        "adaptive_gap": mean_curve_gap(ber, "Adaptive_fixed", "Adaptive_float"),
        "gs16_gap": mean_curve_gap(ber, "GS16_fixed", "GS16_float"),
        "adaptive_vs_gs16_fixed": mean_curve_gap(ber, "Adaptive_fixed", "GS16_fixed"),
        "adaptive_vs_mmse_float": mean_curve_gap(ber, "Adaptive_fixed", "MMSE_float"),
        "fixed_avg_iters": float(np.mean(mode["fixed_avg_iters"])),
        "mode_mismatch_rate": float(np.mean(mode["mode_mismatch_rate"])),
        "float_ratio_rtl_mismatch_rate": float(
            np.mean(mode["float_ratio_rtl_mismatch_rate"])
        ),
        "fixed_ratio_rtl_mismatch_rate": float(
            np.mean(mode["fixed_ratio_rtl_mismatch_rate"])
        ),
        "saturation_count": total_saturation(results),
        "nan_inf_count": total_nan_inf(results),
    }


def profile_recommendation(metrics):
    ber_gap_ok = abs(metrics["adaptive_gap"]) < 1e-3
    mismatch_ok = metrics["mode_mismatch_rate"] < 0.01
    no_sat = metrics["saturation_count"] == 0
    no_nan = metrics["nan_inf_count"] == 0
    if ber_gap_ok and mismatch_ok and no_sat and no_nan:
        return "ACCEPT"
    if abs(metrics["adaptive_gap"]) < 3e-3 and no_nan:
        return "WARNING"
    return "REJECT"


def print_ber_table(results):
    ber = results["ber"]
    print("BER table")
    print(
        f"{'SNR':>5} "
        f"{'MMSE_float':>12} "
        f"{'GS16_float':>12} "
        f"{'Adaptive_float':>15} "
        f"{'GS16_fixed':>12} "
        f"{'Adaptive_fixed':>15}"
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


def print_fixed_gap_summary(results):
    metrics = compute_main_metrics(results)
    print()
    print("Fixed-point BER gap summary")
    print(
        f"- Adaptive fixed vs Adaptive float: avg gap = {metrics['adaptive_gap']:.5e}"
    )
    print(
        "- Adaptive fixed vs GS16 fixed: "
        f"avg gap = {metrics['adaptive_vs_gs16_fixed']:.5e}"
    )
    print(f"- GS16 fixed vs GS16 float: avg gap = {metrics['gs16_gap']:.5e}")
    print(
        "- Adaptive fixed vs MMSE float: "
        f"avg gap = {metrics['adaptive_vs_mmse_float']:.5e}"
    )


def print_iteration_and_modes(results):
    mode = results["mode"]
    print()
    print("Average adaptive iterations and mode mismatch")
    print(
        f"{'SNR':>5} "
        f"{'Float iters':>12} "
        f"{'Fixed iters':>12} "
        f"{'Mode mism':>10} "
        f"{'F rtl':>9} "
        f"{'Q rtl':>9} "
        f"{'F GS4':>8} {'F GS8':>8} {'F GS16':>8} "
        f"{'Q GS4':>8} {'Q GS8':>8} {'Q GS16':>8}"
    )
    for idx, snr_db in enumerate(SNR_DB_LIST):
        print(
            f"{snr_db:5d} "
            f"{mode['float_avg_iters'][idx]:12.3f} "
            f"{mode['fixed_avg_iters'][idx]:12.3f} "
            f"{mode['mode_mismatch_rate'][idx]:10.4f} "
            f"{mode['float_ratio_rtl_mismatch_rate'][idx]:9.4f} "
            f"{mode['fixed_ratio_rtl_mismatch_rate'][idx]:9.4f} "
            f"{mode['float_mode_fraction'][0][idx]:8.3f} "
            f"{mode['float_mode_fraction'][1][idx]:8.3f} "
            f"{mode['float_mode_fraction'][2][idx]:8.3f} "
            f"{mode['fixed_mode_fraction'][0][idx]:8.3f} "
            f"{mode['fixed_mode_fraction'][1][idx]:8.3f} "
            f"{mode['fixed_mode_fraction'][2][idx]:8.3f}"
        )

    if mode["mismatch_examples"]:
        print()
        print("RTL-style selector mismatch examples:")
        for example in mode["mismatch_examples"][:5]:
            print(f"- {example}")


def print_saturation_report(results):
    print()
    print("Saturation/overflow report")
    print(
        f"{'SNR':>5} {'sat':>10} {'overflow':>10} {'nan/inf':>8} "
        f"{'input':>8} {'G':>8} {'b':>8} {'W':>8} {'recip':>8} "
        f"{'gs_mac':>8} {'gs_upd':>8} "
        f"{'max|H|':>9} {'max|y|':>9} {'max|G|':>9} {'max|b|':>9} "
        f"{'max|W|':>9} {'max|x|':>9}"
    )
    for idx, snr_db in enumerate(SNR_DB_LIST):
        stats = results["stats"][idx]
        block = stats.block_saturation
        max_abs = stats.max_abs
        print(
            f"{snr_db:5d} "
            f"{stats.saturation_count:10d} "
            f"{stats.overflow_count:10d} "
            f"{stats.nan_inf_count:8d} "
            f"{block.get('input_quant', 0):8d} "
            f"{block.get('gram_matrix', 0):8d} "
            f"{block.get('matched_filter', 0):8d} "
            f"{block.get('W_regularization', 0):8d} "
            f"{block.get('reciprocal', 0):8d} "
            f"{block.get('gs_mac', 0):8d} "
            f"{block.get('gs_update', 0):8d} "
            f"{max_abs.get('H', 0.0):9.3f} "
            f"{max_abs.get('y', 0.0):9.3f} "
            f"{max_abs.get('G', 0.0):9.3f} "
            f"{max_abs.get('b', 0.0):9.3f} "
            f"{max_abs.get('W', 0.0):9.3f} "
            f"{max_abs.get('x_hat', 0.0):9.3f}"
        )


def print_quantization_error_summary(results):
    print()
    print("Quantization error summary")
    print(
        f"{'SNR':>5} "
        f"{'G avg':>10} {'G rms':>10} "
        f"{'b avg':>10} {'b rms':>10} "
        f"{'W avg':>10} {'W rms':>10} "
        f"{'x16 avg':>10} {'x16 rms':>10}"
    )
    for idx, snr_db in enumerate(SNR_DB_LIST):
        err = results["errors"][idx]
        print(
            f"{snr_db:5d} "
            f"{err['G']['avg_abs']:10.4e} {err['G']['rms']:10.4e} "
            f"{err['b']['avg_abs']:10.4e} {err['b']['rms']:10.4e} "
            f"{err['W']['avg_abs']:10.4e} {err['W']['rms']:10.4e} "
            f"{err['x_gs16']['avg_abs']:10.4e} {err['x_gs16']['rms']:10.4e}"
        )


def run_checks(results, num_frames, validate=False):
    ber = results["ber"]
    metrics = compute_main_metrics(results)
    avg_adaptive_fixed = float(np.mean(ber["Adaptive_fixed"]))
    avg_gs8_fixed = float(np.mean(ber["GS8_fixed"]))
    avg_saturation_per_frame = metrics["saturation_count"] / (
        num_frames * len(SNR_DB_LIST)
    )

    checks = {
        "Fixed-point BER does not become random": avg_adaptive_fixed < 0.25,
        "Adaptive fixed not much worse than fixed GS-8": avg_adaptive_fixed
        <= avg_gs8_fixed + 0.02,
        "Fixed GS16 reasonably close to float GS16": abs(metrics["gs16_gap"]) < 0.02,
        "Saturation count is not excessive": avg_saturation_per_frame < 5.0,
        "No NaN or Inf in fixed detector outputs": metrics["nan_inf_count"] == 0,
    }
    if validate:
        checks.update(
            {
                "Validate adaptive fixed gap < 1e-3": abs(metrics["adaptive_gap"]) < 1e-3,
                "Validate GS16 fixed gap < 1e-3": abs(metrics["gs16_gap"]) < 1e-3,
                "Validate mode mismatch < 1%": metrics["mode_mismatch_rate"] < 0.01,
                "Validate saturation count == 0": metrics["saturation_count"] == 0,
            }
        )

    print()
    print("Correctness checks")
    for label, passed in checks.items():
        print(f"- {label}: {'PASS' if passed else 'FAIL'}")
    return checks


def plot_ber(results):
    ber = results["ber"]
    plt.figure(figsize=(9, 6))
    curves = [
        ("MMSE_float", "-"),
        ("GS4_float", "--"),
        ("GS8_float", "--"),
        ("GS16_float", "--"),
        ("Adaptive_float", "-"),
        ("GS4_fixed", ":"),
        ("GS8_fixed", ":"),
        ("GS16_fixed", ":"),
        ("Adaptive_fixed", "-"),
    ]
    for name, linestyle in curves:
        plt.semilogy(
            SNR_DB_LIST, ber[name], marker="o", linewidth=1.6, linestyle=linestyle, label=name
        )
    plt.grid(True, which="both", linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("BER")
    plt.title("Phase 3 Fixed-Point vs Floating-Point 4x4 MIMO")
    plt.legend(fontsize=8)
    plt.tight_layout()
    output_path = OUTPUT_DIR / "phase3_ber_fixed_vs_float_4x4.png"
    plt.savefig(output_path, dpi=300)
    plt.close()
    print(f"Saved BER plot: {output_path}")


def plot_adaptive_gap(results):
    ber = results["ber"]
    plt.figure(figsize=(8, 5))
    gaps = {
        "Adaptive fixed - Adaptive float": np.asarray(ber["Adaptive_fixed"])
        - np.asarray(ber["Adaptive_float"]),
        "Adaptive fixed - GS16 fixed": np.asarray(ber["Adaptive_fixed"])
        - np.asarray(ber["GS16_fixed"]),
        "GS16 fixed - GS16 float": np.asarray(ber["GS16_fixed"])
        - np.asarray(ber["GS16_float"]),
    }
    for label, values in gaps.items():
        plt.plot(SNR_DB_LIST, values, marker="o", linewidth=1.8, label=label)
    plt.grid(True, linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("BER gap")
    plt.title("Phase 3 Fixed-Point BER Gap")
    plt.legend()
    plt.tight_layout()
    output_path = OUTPUT_DIR / "phase3_adaptive_fixed_gap_4x4.png"
    plt.savefig(output_path, dpi=300)
    plt.close()
    print(f"Saved adaptive-gap plot: {output_path}")


def plot_average_iterations(results):
    mode = results["mode"]
    plt.figure(figsize=(8, 5))
    plt.plot(
        SNR_DB_LIST,
        mode["float_avg_iters"],
        marker="o",
        linewidth=1.8,
        label="Adaptive float",
    )
    plt.plot(
        SNR_DB_LIST,
        mode["fixed_avg_iters"],
        marker="o",
        linewidth=1.8,
        label="Adaptive fixed",
    )
    plt.axhline(16, linestyle="--", linewidth=1.2, label="Fixed GS-16")
    plt.axhline(8, linestyle="--", linewidth=1.2, label="Fixed GS-8")
    plt.axhline(4, linestyle="--", linewidth=1.2, label="Fixed GS-4")
    plt.grid(True, linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("Average GS iterations")
    plt.title("Phase 3 Average Iterations")
    plt.legend()
    plt.tight_layout()
    output_path = OUTPUT_DIR / "phase3_avg_iters_fixed_vs_float_4x4.png"
    plt.savefig(output_path, dpi=300)
    plt.close()
    print(f"Saved average-iterations plot: {output_path}")


def plot_mode_mismatch(results):
    plt.figure(figsize=(8, 5))
    plt.plot(
        SNR_DB_LIST,
        results["mode"]["mode_mismatch_rate"],
        marker="o",
        linewidth=1.8,
        label="float ratio vs fixed RTL",
    )
    plt.plot(
        SNR_DB_LIST,
        results["mode"]["float_ratio_rtl_mismatch_rate"],
        marker="o",
        linewidth=1.8,
        label="float ratio vs float RTL",
    )
    plt.plot(
        SNR_DB_LIST,
        results["mode"]["fixed_ratio_rtl_mismatch_rate"],
        marker="o",
        linewidth=1.8,
        label="fixed ratio vs fixed RTL",
    )
    plt.grid(True, linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("Mode mismatch rate")
    plt.title("Phase 3 Adaptive Mode Selector Mismatch")
    plt.legend()
    plt.tight_layout()
    output_path = OUTPUT_DIR / "phase3_mode_mismatch_4x4.png"
    plt.savefig(output_path, dpi=300)
    plt.close()
    print(f"Saved mode-mismatch plot: {output_path}")


def plot_saturation_count(results):
    total_sat = [stats.saturation_count for stats in results["stats"]]
    plt.figure(figsize=(8, 5))
    plt.plot(SNR_DB_LIST, total_sat, marker="o", linewidth=1.8)
    plt.grid(True, linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("Saturation count")
    plt.title("Phase 3 Fixed-Point Saturation Count")
    plt.tight_layout()
    output_path = OUTPUT_DIR / "phase3_saturation_count_4x4.png"
    plt.savefig(output_path, dpi=300)
    plt.close()
    print(f"Saved saturation-count plot: {output_path}")


def make_plots(results):
    plot_ber(results)
    plot_adaptive_gap(results)
    plot_average_iterations(results)
    plot_mode_mismatch(results)
    plot_saturation_count(results)


def print_phase3_decision(results, checks, reciprocal_sensitivity="not run"):
    metrics = compute_main_metrics(results)
    if (
        abs(metrics["adaptive_gap"]) < 1e-3
        and abs(metrics["gs16_gap"]) < 1e-3
        and metrics["mode_mismatch_rate"] < 0.01
        and metrics["saturation_count"] == 0
        and metrics["nan_inf_count"] == 0
    ):
        q_status = "ACCEPT"
        next_step = "Proceed to Phase 4 scaling study"
    else:
        q_status = "RETUNE"
        next_step = "Run longer validation / tune formats"

    print()
    print("PHASE 3 DECISION:")
    print(f"- Q-format status: {q_status}")
    print("- Recommended formats for RTL:")
    print(
        f"  H={FMT_H.name}, y={FMT_Y.name}, G={FMT_G.name}, b={FMT_B.name}, "
        f"W={FMT_W.name}, ACC={FMT_ACC.name}, x={FMT_X.name}, "
        f"x_out={FMT_X_OUT.name}, reciprocal=exact or Q4.20 pending sweep"
    )
    print(
        "- Fixed vs float BER status: "
        f"adaptive gap {metrics['adaptive_gap']:.5e}, GS16 gap {metrics['gs16_gap']:.5e}"
    )
    print(
        "- Mode selector stability: "
        f"mode mismatch {metrics['mode_mismatch_rate']:.5f}, "
        f"float RTL mismatch {metrics['float_ratio_rtl_mismatch_rate']:.5f}, "
        f"fixed RTL mismatch {metrics['fixed_ratio_rtl_mismatch_rate']:.5f}"
    )
    print(
        "- Saturation/overflow status: "
        f"saturation={metrics['saturation_count']}, nan/inf={metrics['nan_inf_count']}"
    )
    print(f"- Reciprocal sensitivity: {reciprocal_sensitivity}")
    print(f"- Recommended next step: {next_step}")
    if not all(checks.values()):
        print("- Note: one or more checks failed; inspect tables before Phase 4.")


def run_main_simulation(num_frames, seed, reciprocal_mode, run_label):
    print("Phase 3 fixed-point 4x4 adaptive GS MIMO simulation")
    print(f"Run mode: {run_label}")
    print(f"NT = {NT}, NR = {NR}, frames/SNR = {num_frames}, seed = {seed}")
    print(f"Format profile: {ACTIVE_PROFILE.name}")
    print(f"Reciprocal mode: {reciprocal_mode}")
    print("Adaptive policy: aggressive, fixed selector uses RTL-friendly cross multiply")
    print("Mode 0 = GS-4, Mode 1 = GS-8, Mode 2 = GS-16")
    print(f"SNR points: {SNR_DB_LIST}")
    print()

    results = simulate(
        num_frames=num_frames,
        seed=seed,
        reciprocal_mode=reciprocal_mode,
        store_examples=True,
    )
    print_ber_table(results)
    print_fixed_gap_summary(results)
    print_iteration_and_modes(results)
    print_saturation_report(results)
    print_quantization_error_summary(results)
    checks = run_checks(results, num_frames, validate=(run_label == "VALIDATE"))
    print_phase3_decision(results, checks)
    make_plots(results)
    return results


def run_format_sweep(num_frames, seed, reciprocal_mode):
    print("Phase 3 format sweep")
    print(f"Frames/SNR = {num_frames}, seed = {seed}, reciprocal = {reciprocal_mode}")
    print()
    rows = []

    original_profile = ACTIVE_PROFILE.name
    for profile_name in FORMAT_PROFILES:
        set_active_profile(profile_name)
        results = simulate(
            num_frames=num_frames, seed=seed, reciprocal_mode=reciprocal_mode
        )
        metrics = compute_main_metrics(results)
        recommendation = profile_recommendation(metrics)
        row = {"profile": profile_name, "recommendation": recommendation, **metrics}
        rows.append(row)

    set_active_profile(original_profile)

    print(
        f"{'Profile':>25} {'Adapt BER':>11} {'Adapt gap':>11} "
        f"{'GS16 gap':>11} {'Iters':>8} {'Mismatch':>9} "
        f"{'Sat':>8} {'NaN/Inf':>8} {'Rec':>8}"
    )
    for row in rows:
        print(
            f"{row['profile']:>25} "
            f"{row['adaptive_fixed_avg_ber']:11.5e} "
            f"{row['adaptive_gap']:11.5e} "
            f"{row['gs16_gap']:11.5e} "
            f"{row['fixed_avg_iters']:8.3f} "
            f"{row['mode_mismatch_rate']:9.5f} "
            f"{row['saturation_count']:8d} "
            f"{row['nan_inf_count']:8d} "
            f"{row['recommendation']:>8}"
        )

    plot_format_sweep(rows)
    return rows


def plot_format_sweep(rows):
    labels = [row["profile"] for row in rows]
    x = np.arange(len(labels))
    adaptive_gap = [abs(row["adaptive_gap"]) for row in rows]
    mismatch = [row["mode_mismatch_rate"] for row in rows]
    saturation = [row["saturation_count"] for row in rows]

    fig, axes = plt.subplots(3, 1, figsize=(10, 9), sharex=True)
    axes[0].bar(x, adaptive_gap)
    axes[0].axhline(1e-3, color="g", linestyle="--", linewidth=1)
    axes[0].axhline(3e-3, color="r", linestyle="--", linewidth=1)
    axes[0].set_ylabel("|BER gap|")
    axes[0].set_title("Phase 3 Format Sweep Summary")
    axes[0].grid(True, linestyle=":")

    axes[1].bar(x, mismatch)
    axes[1].axhline(0.01, color="r", linestyle="--", linewidth=1)
    axes[1].set_ylabel("Mode mismatch")
    axes[1].grid(True, linestyle=":")

    axes[2].bar(x, saturation)
    axes[2].set_ylabel("Saturation")
    axes[2].set_xticks(x)
    axes[2].set_xticklabels(labels, rotation=20, ha="right")
    axes[2].grid(True, linestyle=":")

    fig.tight_layout()
    output_path = OUTPUT_DIR / "phase3_format_sweep_summary_4x4.png"
    fig.savefig(output_path, dpi=300)
    plt.close(fig)
    print(f"Saved format-sweep plot: {output_path}")


def run_reciprocal_sweep(num_frames, seed):
    print("Phase 3 reciprocal mode sweep")
    print(f"Frames/SNR = {num_frames}, seed = {seed}, profile = {ACTIVE_PROFILE.name}")
    print()
    rows = []
    baseline = None
    for reciprocal_mode in ("exact", "quantized", "coarse_lut"):
        results = simulate(
            num_frames=num_frames, seed=seed, reciprocal_mode=reciprocal_mode
        )
        if baseline is None:
            baseline = results
        metrics = compute_main_metrics(results)
        adaptive_gap_vs_exact = mean_curve_gap(
            {
                "mode": results["ber"]["Adaptive_fixed"],
                "exact": baseline["ber"]["Adaptive_fixed"],
            },
            "mode",
            "exact",
        )
        gs16_gap_vs_exact = mean_curve_gap(
            {
                "mode": results["ber"]["GS16_fixed"],
                "exact": baseline["ber"]["GS16_fixed"],
            },
            "mode",
            "exact",
        )
        if (
            abs(adaptive_gap_vs_exact) < 1e-3
            and metrics["saturation_count"] == 0
            and metrics["nan_inf_count"] == 0
        ):
            recommendation = "ACCEPT"
        elif abs(adaptive_gap_vs_exact) < 3e-3 and metrics["nan_inf_count"] == 0:
            recommendation = "WARNING"
        else:
            recommendation = "REJECT"
        rows.append(
            {
                "reciprocal_mode": reciprocal_mode,
                "adaptive_fixed_avg_ber": metrics["adaptive_fixed_avg_ber"],
                "adaptive_gap_vs_exact": adaptive_gap_vs_exact,
                "gs16_gap_vs_exact": gs16_gap_vs_exact,
                "saturation_count": metrics["saturation_count"],
                "nan_inf_count": metrics["nan_inf_count"],
                "recommendation": recommendation,
            }
        )

    print(
        f"{'Mode':>12} {'Adapt BER':>11} {'Adapt gap':>12} "
        f"{'GS16 gap':>12} {'Sat':>8} {'NaN/Inf':>8} {'Rec':>8}"
    )
    for row in rows:
        print(
            f"{row['reciprocal_mode']:>12} "
            f"{row['adaptive_fixed_avg_ber']:11.5e} "
            f"{row['adaptive_gap_vs_exact']:12.5e} "
            f"{row['gs16_gap_vs_exact']:12.5e} "
            f"{row['saturation_count']:8d} "
            f"{row['nan_inf_count']:8d} "
            f"{row['recommendation']:>8}"
        )
    plot_reciprocal_sweep(rows)
    return rows


def plot_reciprocal_sweep(rows):
    labels = [row["reciprocal_mode"] for row in rows]
    x = np.arange(len(labels))
    adaptive_gap = [abs(row["adaptive_gap_vs_exact"]) for row in rows]
    gs16_gap = [abs(row["gs16_gap_vs_exact"]) for row in rows]
    saturation = [row["saturation_count"] for row in rows]

    fig, axes = plt.subplots(3, 1, figsize=(8, 8), sharex=True)
    axes[0].bar(x, adaptive_gap)
    axes[0].set_ylabel("|Adapt gap|")
    axes[0].grid(True, linestyle=":")
    axes[0].set_title("Phase 3 Reciprocal Mode Comparison")

    axes[1].bar(x, gs16_gap)
    axes[1].set_ylabel("|GS16 gap|")
    axes[1].grid(True, linestyle=":")

    axes[2].bar(x, saturation)
    axes[2].set_ylabel("Saturation")
    axes[2].set_xticks(x)
    axes[2].set_xticklabels(labels)
    axes[2].grid(True, linestyle=":")

    fig.tight_layout()
    output_path = OUTPUT_DIR / "phase3_reciprocal_mode_comparison_4x4.png"
    fig.savefig(output_path, dpi=300)
    plt.close(fig)
    print(f"Saved reciprocal-mode plot: {output_path}")


def make_stress_channels(rng):
    eye = np.eye(NT, dtype=np.complex128)
    perturb = 0.03 * (
        rng.standard_normal((NR, NT)) + 1j * rng.standard_normal((NR, NT))
    )
    base = (
        rng.standard_normal(NR) + 1j * rng.standard_normal(NR)
    ) / np.sqrt(2)
    correlated = np.column_stack(
        [base + 0.05 * (rng.standard_normal(NR) + 1j * rng.standard_normal(NR)) for _ in range(NT)]
    )
    ill = generate_channel(rng)
    ill[:, 1] = ill[:, 0] + 0.01 * (
        rng.standard_normal(NR) + 1j * rng.standard_normal(NR)
    )
    return [
        ("near_orthogonal", eye + perturb),
        ("highly_correlated", correlated),
        ("ill_conditioned", ill),
        ("large_magnitude", 3.0 * generate_channel(rng)),
        ("small_magnitude", 0.25 * generate_channel(rng)),
    ]


def run_single_frame(H, bits_tx, snr_db, rng, reciprocal_mode):
    x = qpsk_mod(bits_tx)
    y, noise_var = add_awgn(rng, H @ x, snr_db)
    G_float, _, _ = float_reference_matrices(H, y, noise_var)
    gs_float = gs_detector_at_iters(H, y, noise_var, iter_counts=GS_ITERS)
    float_metric = channel_condition_metric_from_G(G_float)
    float_mode = select_adaptive_mode_aggressive(
        snr_db, float_metric["dominance"]
    )
    stats = FixedStats()
    H_q, y_q, G_fixed, b_fixed, W_fixed = fixed_prepare_matrices(H, y, noise_var, stats)
    gs_fixed = fixed_gs_detector_at_iters(
        W_fixed, b_fixed, stats, iter_counts=GS_ITERS, reciprocal_mode=reciprocal_mode
    )
    fixed_metric = channel_condition_metric_from_G(G_fixed)
    fixed_mode = select_adaptive_mode_aggressive_rtl_friendly(
        snr_db, fixed_metric["diag_sum"], fixed_metric["offdiag_sum"]
    )
    adaptive_float_output = gs_float[ADAPTIVE_MODE_ITERS[float_mode]]
    adaptive_fixed_output = gs_fixed[ADAPTIVE_MODE_ITERS[fixed_mode]]
    x_gs16_error = np.asarray(gs_fixed[16]) - np.asarray(gs_float[16])
    x_adaptive_error = np.asarray(adaptive_fixed_output) - np.asarray(adaptive_float_output)
    gs16_detected_match = bool(
        np.array_equal(qpsk_to_bits(gs_fixed[16]), qpsk_to_bits(gs_float[16]))
    )
    adaptive_detected_match = bool(
        np.array_equal(qpsk_to_bits(adaptive_fixed_output), qpsk_to_bits(adaptive_float_output))
    )
    return {
        "x": x,
        "y": y,
        "noise_var": noise_var,
        "H_q": H_q,
        "y_q": y_q,
        "G_fixed": G_fixed,
        "b_fixed": b_fixed,
        "W_fixed": W_fixed,
        "gs_fixed": gs_fixed,
        "gs_float": gs_float,
        "float_metric": float_metric,
        "fixed_metric": fixed_metric,
        "float_mode": float_mode,
        "fixed_mode": fixed_mode,
        "adaptive_float_output": adaptive_float_output,
        "adaptive_fixed_output": adaptive_fixed_output,
        "stats": stats,
        "x_gs16_rms_error": float(np.sqrt(np.mean(np.abs(x_gs16_error) ** 2))),
        "x_adaptive_rms_error": float(np.sqrt(np.mean(np.abs(x_adaptive_error) ** 2))),
        "gs16_detected_match": gs16_detected_match,
        "adaptive_detected_match": adaptive_detected_match,
    }


def run_stress_tests(seed, reciprocal_mode):
    rng = np.random.default_rng(seed)
    print("Phase 3 stress tests")
    print(f"Seed = {seed}, reciprocal = {reciprocal_mode}, profile = {ACTIVE_PROFILE.name}")
    print(
        f"{'Case':>18} {'SNR':>5} {'diag':>10} {'offdiag':>10} {'dom':>8} "
        f"{'Fmode':>6} {'Qmode':>6} {'sat':>6} "
        f"{'x16_rms':>10} {'xa_rms':>10} {'b16':>5} {'badapt':>6} "
        f"{'max|H|':>8} {'max|y|':>8} {'max|W|':>8} {'max|x|':>8}"
    )
    summaries = []
    for case_name, H in make_stress_channels(rng):
        bits_tx = rng.integers(0, 2, size=2 * NT, dtype=np.int8)
        for snr_db in (10, 20):
            result = run_single_frame(H, bits_tx, snr_db, rng, reciprocal_mode)
            fixed_metric = result["fixed_metric"]
            stats = result["stats"]
            max_abs = stats.max_abs
            print(
                f"{case_name:>18} {snr_db:5d} "
                f"{fixed_metric['diag_sum']:10.3f} "
                f"{fixed_metric['offdiag_sum']:10.3f} "
                f"{fixed_metric['dominance']:8.3f} "
                f"{result['float_mode']:6d} "
                f"{result['fixed_mode']:6d} "
                f"{stats.saturation_count:6d} "
                f"{result['x_gs16_rms_error']:10.4e} "
                f"{result['x_adaptive_rms_error']:10.4e} "
                f"{'yes' if result['gs16_detected_match'] else 'no':>5} "
                f"{'yes' if result['adaptive_detected_match'] else 'no':>6} "
                f"{max_abs.get('H', 0.0):8.3f} "
                f"{max_abs.get('y', 0.0):8.3f} "
                f"{max_abs.get('W', 0.0):8.3f} "
                f"{max_abs.get('x_hat', 0.0):8.3f}"
            )
            summaries.append((case_name, snr_db, result))
    return summaries


def complex_to_json(value):
    arr = np.asarray(value)
    if arr.ndim == 0:
        return [float(np.real(arr)), float(np.imag(arr))]
    return np.stack([np.real(arr), np.imag(arr)], axis=-1).tolist()


def int_complex_to_json(value, fmt):
    real, imag = fixed_to_int(value, fmt)
    return np.stack([real, imag], axis=-1).tolist()


def export_rtl_vectors(count, seed, reciprocal_mode):
    output_dir = OUTPUT_DIR / "vectors" / "phase3_rtl_seed_vectors"
    output_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(seed)

    for vector_idx in range(count):
        snr_db = SNR_DB_LIST[vector_idx % len(SNR_DB_LIST)]
        bits_tx = rng.integers(0, 2, size=2 * NT, dtype=np.int8)
        H = generate_channel(rng, n_rx=NR, n_tx=NT)
        result = run_single_frame(H, bits_tx, snr_db, rng, reciprocal_mode)
        fixed_iters = ADAPTIVE_MODE_ITERS[result["fixed_mode"]]
        gs_fixed = result["gs_fixed"]
        adaptive_output = gs_fixed[fixed_iters]
        detected_adaptive = qpsk_to_bits(adaptive_output)

        H_int = fixed_to_int(result["H_q"], FMT_H)
        y_int = fixed_to_int(result["y_q"], FMT_Y)
        G_int = fixed_to_int(result["G_fixed"], FMT_G)
        b_int = fixed_to_int(result["b_fixed"], FMT_B)
        W_int = fixed_to_int(result["W_fixed"], FMT_W)
        x4_int = fixed_to_int(gs_fixed[4], FMT_X_OUT)
        x8_int = fixed_to_int(gs_fixed[8], FMT_X_OUT)
        x16_int = fixed_to_int(gs_fixed[16], FMT_X_OUT)
        xa_int = fixed_to_int(adaptive_output, FMT_X_OUT)

        npz_path = output_dir / f"vector_{vector_idx:03d}.npz"
        np.savez(
            npz_path,
            H_float=H,
            y_float=result["y"],
            H_fixed_quantized=result["H_q"],
            y_fixed_quantized=result["y_q"],
            bits_tx=bits_tx,
            qpsk_symbols=result["x"],
            noise_var=np.array(result["noise_var"]),
            G_fixed=result["G_fixed"],
            b_fixed=result["b_fixed"],
            W_fixed=result["W_fixed"],
            fixed_mode=np.array(result["fixed_mode"]),
            fixed_iterations=np.array(fixed_iters),
            gs4_fixed_output=gs_fixed[4],
            gs8_fixed_output=gs_fixed[8],
            gs16_fixed_output=gs_fixed[16],
            adaptive_fixed_output=adaptive_output,
            detected_bits_adaptive_fixed=detected_adaptive,
            expected_mode=np.array(result["fixed_mode"]),
            expected_detected_bits=detected_adaptive,
            H_fixed_int_real=H_int[0],
            H_fixed_int_imag=H_int[1],
            y_fixed_int_real=y_int[0],
            y_fixed_int_imag=y_int[1],
            G_fixed_int_real=G_int[0],
            G_fixed_int_imag=G_int[1],
            b_fixed_int_real=b_int[0],
            b_fixed_int_imag=b_int[1],
            W_fixed_int_real=W_int[0],
            W_fixed_int_imag=W_int[1],
            gs4_fixed_int_real=x4_int[0],
            gs4_fixed_int_imag=x4_int[1],
            gs8_fixed_int_real=x8_int[0],
            gs8_fixed_int_imag=x8_int[1],
            gs16_fixed_int_real=x16_int[0],
            gs16_fixed_int_imag=x16_int[1],
            adaptive_fixed_int_real=xa_int[0],
            adaptive_fixed_int_imag=xa_int[1],
        )

        json_summary = {
            "vector_id": vector_idx,
            "snr_db": snr_db,
            "noise_var": float(result["noise_var"]),
            "profile": ACTIVE_PROFILE.name,
            "reciprocal_mode": reciprocal_mode,
            "formats": {
                "H": FMT_H.name,
                "y": FMT_Y.name,
                "G": FMT_G.name,
                "b": FMT_B.name,
                "W": FMT_W.name,
                "ACC": FMT_ACC.name,
                "x": FMT_X.name,
                "x_out": FMT_X_OUT.name,
            },
            "bits_tx": bits_tx.tolist(),
            "qpsk_symbols": complex_to_json(result["x"]),
            "H_float": complex_to_json(H),
            "y_float": complex_to_json(result["y"]),
            "H_fixed_quantized": complex_to_json(result["H_q"]),
            "y_fixed_quantized": complex_to_json(result["y_q"]),
            "G_fixed": complex_to_json(result["G_fixed"]),
            "b_fixed": complex_to_json(result["b_fixed"]),
            "W_fixed": complex_to_json(result["W_fixed"]),
            "fixed_mode": result["fixed_mode"],
            "fixed_iterations": fixed_iters,
            "expected_mode": result["fixed_mode"],
            "detected_bits_adaptive_fixed": detected_adaptive.tolist(),
            "expected_detected_bits": detected_adaptive.tolist(),
            "gs4_fixed_output": complex_to_json(gs_fixed[4]),
            "gs8_fixed_output": complex_to_json(gs_fixed[8]),
            "gs16_fixed_output": complex_to_json(gs_fixed[16]),
            "adaptive_fixed_output": complex_to_json(adaptive_output),
            "H_fixed_int": int_complex_to_json(result["H_q"], FMT_H),
            "y_fixed_int": int_complex_to_json(result["y_q"], FMT_Y),
            "G_fixed_int": int_complex_to_json(result["G_fixed"], FMT_G),
            "b_fixed_int": int_complex_to_json(result["b_fixed"], FMT_B),
            "W_fixed_int": int_complex_to_json(result["W_fixed"], FMT_W),
            "x_outputs_int": {
                "gs4": int_complex_to_json(gs_fixed[4], FMT_X_OUT),
                "gs8": int_complex_to_json(gs_fixed[8], FMT_X_OUT),
                "gs16": int_complex_to_json(gs_fixed[16], FMT_X_OUT),
                "adaptive": int_complex_to_json(adaptive_output, FMT_X_OUT),
            },
            "npz_file": npz_path.name,
        }

        json_path = output_dir / f"vector_{vector_idx:03d}.json"
        json_path.write_text(json.dumps(json_summary, indent=2), encoding="utf-8")

    print(f"Exported {count} RTL seed vectors to: {output_dir}")
    return output_dir


def resolve_frames(args, sweep=False):
    if args.quick:
        return QUICK_FRAMES, "QUICK"
    if args.validate:
        return VALIDATE_FRAMES, "VALIDATE"
    if args.num_frames is not None:
        return args.num_frames, "CUSTOM"
    if sweep:
        return QUICK_FRAMES, "QUICK"
    return NUM_FRAMES, "FULL"


def parse_args():
    parser = ArgumentParser(description="Phase 3 fixed-point 4x4 adaptive GS MIMO model")
    parser.add_argument("--num-frames", type=int, default=None)
    parser.add_argument("--quick", action="store_true", help="Run 2000 frames per SNR")
    parser.add_argument("--validate", action="store_true", help="Run 5000 frames per SNR")
    parser.add_argument("--seed", type=int, default=RNG_SEED)
    parser.add_argument(
        "--reciprocal-mode",
        choices=("exact", "quantized", "coarse_lut"),
        default="exact",
    )
    parser.add_argument("--format-sweep", action="store_true")
    parser.add_argument("--reciprocal-sweep", action="store_true")
    parser.add_argument("--stress-tests", action="store_true")
    parser.add_argument("--export-rtl-vectors", type=int, default=0)
    return parser.parse_args()


def main():
    args = parse_args()
    set_active_profile("safe_current")
    experiments_requested = (
        args.format_sweep
        or args.reciprocal_sweep
        or args.stress_tests
        or args.export_rtl_vectors > 0
    )

    if not experiments_requested:
        frames, run_label = resolve_frames(args, sweep=False)
        run_main_simulation(
            num_frames=frames,
            seed=args.seed,
            reciprocal_mode=args.reciprocal_mode,
            run_label=run_label,
        )
        return

    if args.format_sweep:
        frames, run_label = resolve_frames(args, sweep=True)
        print(f"Format sweep run mode: {run_label}")
        run_format_sweep(frames, args.seed, args.reciprocal_mode)

    if args.reciprocal_sweep:
        frames, run_label = resolve_frames(args, sweep=True)
        print(f"Reciprocal sweep run mode: {run_label}")
        set_active_profile("safe_current")
        run_reciprocal_sweep(frames, args.seed)

    if args.stress_tests:
        set_active_profile("safe_current")
        run_stress_tests(args.seed, args.reciprocal_mode)

    if args.export_rtl_vectors > 0:
        set_active_profile("safe_current")
        export_rtl_vectors(args.export_rtl_vectors, args.seed, args.reciprocal_mode)


if __name__ == "__main__":
    main()
