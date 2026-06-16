from argparse import ArgumentParser
from pathlib import Path
import json

import numpy as np


NR = 4
NT = 4

H_W = 16
H_FRAC = 12
Y_W = 16
Y_FRAC = 12
GBW_W = 20
GBW_FRAC = 12
ACC_W = 28
ACC_FRAC = 16
X_W = 22
X_FRAC = 16
XOUT_W = 16
XOUT_FRAC = 12

MODE_ITERS = {0: 4, 1: 8, 2: 16}
PROJECT_ROOT = Path(__file__).resolve().parents[1]


def wrap_signed(value, width):
    value = int(value)
    modulus = 1 << width
    value &= modulus - 1
    if value >= (1 << (width - 1)):
        value -= modulus
    return value


def wrap_unsigned(value, width):
    return int(value) & ((1 << width) - 1)


def sat_signed(value, width):
    lo = -(1 << (width - 1))
    hi = (1 << (width - 1)) - 1
    return max(lo, min(hi, int(value)))


def trunc_div(numer, denom):
    numer = int(numer)
    denom = int(denom)
    if denom == 0:
        return 0
    sign = -1 if (numer < 0) ^ (denom < 0) else 1
    return sign * (abs(numer) // abs(denom))


def quantize_to_int(value, width, frac):
    scaled = np.rint(np.asarray(value) * (1 << frac)).astype(np.int64)
    lo = -(1 << (width - 1))
    hi = (1 << (width - 1)) - 1
    return np.clip(scaled, lo, hi).astype(np.int64)


def qpsk_mod(bits):
    bits = np.asarray(bits, dtype=np.int8).reshape(-1, 2)
    real = 1 - 2 * bits[:, 1]
    imag = 1 - 2 * bits[:, 0]
    return (real + 1j * imag) / np.sqrt(2)


def snr_to_level(snr_db):
    if snr_db >= 8:
        return 2
    if snr_db >= 4:
        return 1
    return 0


def add_awgn(rng, signal, snr_db, noise_var_override=None):
    if noise_var_override is not None:
        return signal.copy(), noise_var_override
    noise_var = 1.0 / (10 ** (snr_db / 10.0))
    noise = np.sqrt(noise_var / 2.0) * (
        rng.standard_normal(signal.shape) + 1j * rng.standard_normal(signal.shape)
    )
    return signal + noise, noise_var


def acc_to_gbw(value):
    shift = ACC_FRAC - GBW_FRAC
    if shift >= 0:
        return wrap_signed(int(value) >> shift, GBW_W)
    return wrap_signed(int(value) << (-shift), GBW_W)


def rtl_gram_matrix(H_re, H_im):
    G_re = np.zeros((NT, NT), dtype=np.int64)
    G_im = np.zeros((NT, NT), dtype=np.int64)
    shift_to_acc = (2 * H_FRAC) - ACC_FRAC

    for i in range(NT):
        for j in range(NT):
            acc_re = 0
            acc_im = 0
            for r in range(NR):
                a_re = wrap_signed(H_re[r, i], H_W)
                a_im = wrap_signed(-int(H_im[r, i]), H_W)
                b_re = wrap_signed(H_re[r, j], H_W)
                b_im = wrap_signed(H_im[r, j], H_W)

                ac = wrap_signed(a_re * b_re, 2 * H_W)
                bd = wrap_signed(a_im * b_im, 2 * H_W)
                ad = wrap_signed(a_re * b_im, 2 * H_W)
                bc = wrap_signed(a_im * b_re, 2 * H_W)

                re_full = wrap_signed(ac - bd, 2 * H_W + 1)
                im_full = wrap_signed(ad + bc, 2 * H_W + 1)
                prod_re = wrap_signed(re_full >> shift_to_acc, ACC_W)
                prod_im = wrap_signed(im_full >> shift_to_acc, ACC_W)

                acc_re = wrap_signed(acc_re + prod_re, ACC_W)
                acc_im = wrap_signed(acc_im + prod_im, ACC_W)

            G_re[i, j] = acc_to_gbw(acc_re)
            G_im[i, j] = acc_to_gbw(acc_im)
    return G_re, G_im


def rtl_matched_filter(H_re, H_im, y_re, y_im):
    b_re = np.zeros(NT, dtype=np.int64)
    b_im = np.zeros(NT, dtype=np.int64)
    shift_to_acc = H_FRAC + Y_FRAC - ACC_FRAC

    for i in range(NT):
        acc_re = 0
        acc_im = 0
        for r in range(NR):
            a_re = wrap_signed(H_re[r, i], H_W)
            a_im = wrap_signed(-int(H_im[r, i]), H_W)
            c_re = wrap_signed(y_re[r], Y_W)
            c_im = wrap_signed(y_im[r], Y_W)

            ac = wrap_signed(a_re * c_re, H_W + Y_W)
            bd = wrap_signed(a_im * c_im, H_W + Y_W)
            ad = wrap_signed(a_re * c_im, H_W + Y_W)
            bc = wrap_signed(a_im * c_re, H_W + Y_W)

            re_full = wrap_signed(ac - bd, H_W + Y_W + 1)
            im_full = wrap_signed(ad + bc, H_W + Y_W + 1)
            prod_re = wrap_signed(re_full >> shift_to_acc, ACC_W)
            prod_im = wrap_signed(im_full >> shift_to_acc, ACC_W)

            acc_re = wrap_signed(acc_re + prod_re, ACC_W)
            acc_im = wrap_signed(acc_im + prod_im, ACC_W)

        b_re[i] = acc_to_gbw(acc_re)
        b_im[i] = acc_to_gbw(acc_im)
    return b_re, b_im


def rtl_regularize(G_re, G_im, noise_var_int):
    W_re = np.array(G_re, dtype=np.int64, copy=True)
    W_im = np.array(G_im, dtype=np.int64, copy=True)
    for i in range(NT):
        W_re[i, i] = wrap_signed(int(G_re[i, i]) + int(noise_var_int), GBW_W)
    return W_re, W_im


def abs_signed_for_metric(value, width):
    value = wrap_signed(value, width)
    if value < 0:
        return wrap_unsigned(-value, width)
    return wrap_unsigned(value, width)


def rtl_condition_metric(G_re, G_im):
    diag_sum = 0
    offdiag_sum = 0
    for i in range(NT):
        for j in range(NT):
            mag = wrap_unsigned(
                abs_signed_for_metric(G_re[i, j], GBW_W)
                + abs_signed_for_metric(G_im[i, j], GBW_W),
                32,
            )
            if i == j:
                diag_sum = wrap_unsigned(diag_sum + mag, 32)
            else:
                offdiag_sum = wrap_unsigned(offdiag_sum + mag, 32)
    return diag_sum, offdiag_sum


def rtl_select_mode(snr_level, diag_sum, offdiag_sum):
    lhs_100 = wrap_unsigned(diag_sum * 100, 40)
    rhs_105 = wrap_unsigned(offdiag_sum * 105, 40)
    rhs_80 = wrap_unsigned(offdiag_sum * 80, 40)
    if snr_level >= 2 and lhs_100 >= rhs_105:
        return 0, 4
    if snr_level >= 1 and lhs_100 >= rhs_80:
        return 1, 8
    return 2, 16


def b_to_acc(value):
    shift = ACC_FRAC - GBW_FRAC
    if shift >= 0:
        return wrap_signed(int(value) << shift, ACC_W)
    return wrap_signed(int(value) >> (-shift), ACC_W)


def mult_wx_to_acc(w, x):
    prod_w = GBW_W + X_W
    prod_frac = GBW_FRAC + X_FRAC
    shift = prod_frac - ACC_FRAC
    prod = wrap_signed(int(w) * int(x), prod_w)
    if shift >= 0:
        return wrap_signed(prod >> shift, ACC_W)
    return wrap_signed(prod << (-shift), ACC_W)


def div_q_to_x(num, den):
    div_shift = X_FRAC + GBW_FRAC - ACC_FRAC
    div_w = ACC_W + X_FRAC + GBW_FRAC
    den = wrap_signed(den, GBW_W)
    if den == 0:
        return 0
    if div_shift >= 0:
        num_shift = wrap_signed(int(num) << div_shift, div_w)
    else:
        num_shift = wrap_signed(int(num) >> (-div_shift), div_w)
    quot = wrap_signed(trunc_div(num_shift, den), div_w)
    return wrap_signed(quot, X_W)


def rtl_gs_solver(W_re, W_im, b_re, b_im, num_iters):
    x_re = [0] * NT
    x_im = [0] * NT
    for i in range(NT):
        x_re[i] = div_q_to_x(b_to_acc(b_re[i]), W_re[i, i])
        x_im[i] = div_q_to_x(b_to_acc(b_im[i]), W_re[i, i])

    for _ in range(num_iters):
        x_old_re = list(x_re)
        x_old_im = list(x_im)
        for i in range(NT):
            sum_re = 0
            sum_im = 0
            for j in range(NT):
                if j == i:
                    continue
                if j < i:
                    xj_re = x_re[j]
                    xj_im = x_im[j]
                else:
                    xj_re = x_old_re[j]
                    xj_im = x_old_im[j]

                prod_re = wrap_signed(
                    mult_wx_to_acc(W_re[i, j], xj_re)
                    - mult_wx_to_acc(W_im[i, j], xj_im),
                    ACC_W,
                )
                prod_im = wrap_signed(
                    mult_wx_to_acc(W_re[i, j], xj_im)
                    + mult_wx_to_acc(W_im[i, j], xj_re),
                    ACC_W,
                )
                sum_re = wrap_signed(sum_re + prod_re, ACC_W)
                sum_im = wrap_signed(sum_im + prod_im, ACC_W)

            numerator_re = wrap_signed(b_to_acc(b_re[i]) - sum_re, ACC_W)
            numerator_im = wrap_signed(b_to_acc(b_im[i]) - sum_im, ACC_W)
            x_re[i] = div_q_to_x(numerator_re, W_re[i, i])
            x_im[i] = div_q_to_x(numerator_im, W_re[i, i])
    return np.array(x_re, dtype=np.int64), np.array(x_im, dtype=np.int64)


def rtl_x_to_xout(x_values):
    shift = X_FRAC - XOUT_FRAC
    out = []
    for value in x_values:
        if shift >= 0:
            shifted = int(value) >> shift
        else:
            shifted = int(value) << (-shift)
        out.append(sat_signed(shifted, XOUT_W))
    return np.array(out, dtype=np.int64)


def rtl_slice_bits(xout_re, xout_im):
    bits = []
    for re, im in zip(xout_re, xout_im):
        imag_sign = 1 if int(im) < 0 else 0
        real_sign = 1 if int(re) < 0 else 0
        bits.append((imag_sign << 1) | real_sign)
    return bits


def complex_to_pairs(value):
    arr = np.asarray(value)
    return np.stack([np.real(arr), np.imag(arr)], axis=-1).tolist()


def fixed_case_identity():
    bits = np.array([0, 0, 0, 1, 1, 1, 1, 0], dtype=np.int8)
    H = np.eye(NR, NT, dtype=np.complex128)
    return {
        "case_name": "identity_noise0_high_snr",
        "bits_tx": bits,
        "H": H,
        "snr_db": 20,
        "noise_var_override": 0.0,
    }


def fixed_case_diagonal_scaled(rng):
    bits = rng.integers(0, 2, size=2 * NT, dtype=np.int8)
    scales = np.array([1.0, 0.75, 1.25, 0.5])
    H = np.diag(scales).astype(np.complex128)
    return {
        "case_name": "diagonal_scaled_noise0_high_snr",
        "bits_tx": bits,
        "H": H,
        "snr_db": 20,
        "noise_var_override": 0.0,
    }


def fixed_case_real_coupled(rng):
    bits = rng.integers(0, 2, size=2 * NT, dtype=np.int8)
    H = np.array(
        [
            [1.00, 0.20, 0.00, 0.00],
            [0.15, 1.00, 0.15, 0.00],
            [0.00, 0.20, 1.00, 0.20],
            [0.00, 0.00, 0.15, 1.00],
        ],
        dtype=np.complex128,
    )
    return {
        "case_name": "real_nondiagonal_coupled_noise0_high_snr",
        "bits_tx": bits,
        "H": H,
        "snr_db": 20,
        "noise_var_override": 0.0,
    }


def fixed_case_weak_dominance(rng):
    bits = rng.integers(0, 2, size=2 * NT, dtype=np.int8)
    base = (rng.standard_normal(NR) + 1j * rng.standard_normal(NR)) / np.sqrt(2)
    H = np.zeros((NR, NT), dtype=np.complex128)
    for c in range(NT):
        perturb = 0.04 * (
            rng.standard_normal(NR) + 1j * rng.standard_normal(NR)
        )
        H[:, c] = base + perturb
    return {
        "case_name": "weak_dominance_correlated_12db",
        "bits_tx": bits,
        "H": H,
        "snr_db": 12,
        "noise_var_override": None,
    }


def fixed_bits_pattern(index):
    patterns = [
        [0, 0, 0, 1, 1, 1, 1, 0],
        [1, 1, 1, 0, 1, 1, 1, 1],
        [0, 0, 1, 1, 1, 0, 1, 0],
        [1, 1, 1, 1, 0, 1, 0, 0],
        [0, 1, 0, 1, 1, 0, 0, 1],
        [1, 0, 0, 0, 0, 1, 1, 1],
    ]
    return np.array(patterns[index % len(patterns)], dtype=np.int8)


def uart_case_diagonal_variant(index, snr_db):
    scale_sets = [
        [1.0, 0.75, 1.25, 0.5],
        [0.9, 1.1, 0.8, 1.2],
        [1.3, 0.7, 1.0, 0.6],
        [0.65, 1.2, 0.95, 1.35],
    ]
    H = np.diag(scale_sets[index % len(scale_sets)]).astype(np.complex128)
    return {
        "case_name": f"uart_diag_variant_{snr_db}db_{index}",
        "bits_tx": fixed_bits_pattern(index),
        "H": H,
        "snr_db": snr_db,
        "noise_var_override": None,
    }


def uart_case_real_coupled(index, snr_db, coupling):
    H = np.eye(NR, NT, dtype=np.complex128)
    for i in range(NT - 1):
        H[i, i + 1] = coupling + 0.02 * ((index + i) % 3)
        H[i + 1, i] = 0.75 * coupling + 0.01 * ((index + i) % 2)
    return {
        "case_name": f"uart_real_coupled_{snr_db}db_c{int(coupling * 100)}_{index}",
        "bits_tx": fixed_bits_pattern(index + 2),
        "H": H,
        "snr_db": snr_db,
        "noise_var_override": None,
    }


def uart_case_complex_coupled(index, snr_db, coupling):
    H = np.eye(NR, NT, dtype=np.complex128)
    for i in range(NT - 1):
        H[i, i + 1] = coupling + 1j * (coupling / 2.0 + 0.01 * ((index + i) % 2))
        H[i + 1, i] = 0.6 * coupling - 1j * (coupling / 3.0 + 0.015 * ((index + i) % 3))
    H[0, 2] = 0.03j * ((index % 3) + 1)
    H[2, 0] = -0.02j * (((index + 1) % 3) + 1)
    return {
        "case_name": f"uart_complex_coupled_{snr_db}db_c{int(coupling * 100)}_{index}",
        "bits_tx": fixed_bits_pattern(index + 3),
        "H": H,
        "snr_db": snr_db,
        "noise_var_override": None,
    }


def uart_case_correlated(index, snr_db):
    local_rng = np.random.default_rng(1000 + index)
    base = (local_rng.standard_normal(NR) + 1j * local_rng.standard_normal(NR)) / np.sqrt(2)
    H = np.zeros((NR, NT), dtype=np.complex128)
    for c in range(NT):
        perturb = 0.03 * (
            local_rng.standard_normal(NR) + 1j * local_rng.standard_normal(NR)
        )
        H[:, c] = base + perturb
    return {
        "case_name": f"uart_correlated_{snr_db}db_{index}",
        "bits_tx": fixed_bits_pattern(index + 4),
        "H": H,
        "snr_db": snr_db,
        "noise_var_override": None,
    }


def random_rayleigh_case(rng, snr_db, index):
    bits = rng.integers(0, 2, size=2 * NT, dtype=np.int8)
    H = (rng.standard_normal((NR, NT)) + 1j * rng.standard_normal((NR, NT))) / np.sqrt(2)
    return {
        "case_name": f"random_rayleigh_{snr_db}db_{index}",
        "bits_tx": bits,
        "H": H,
        "snr_db": snr_db,
        "noise_var_override": None,
    }


def build_case_specs(num_vectors, rng):
    specs = [
        fixed_case_identity(),
        fixed_case_diagonal_scaled(rng),
        fixed_case_real_coupled(rng),
        random_rayleigh_case(rng, 4, 0),
        random_rayleigh_case(rng, 8, 0),
        random_rayleigh_case(rng, 12, 0),
        fixed_case_weak_dominance(rng),
    ]
    snr_cycle = [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20]
    idx = 0
    while len(specs) < num_vectors:
        snr_db = snr_cycle[idx % len(snr_cycle)]
        specs.append(random_rayleigh_case(rng, snr_db, idx + 1))
        idx += 1
    return specs[:num_vectors]


def build_uart_extra_case_specs(rng):
    specs = []
    for idx in range(8):
        specs.append(uart_case_diagonal_variant(idx, 20))
    for idx in range(5):
        specs.append(uart_case_real_coupled(idx, 20, 0.08))
    for idx in range(5):
        specs.append(uart_case_complex_coupled(idx, 20, 0.06))
    for idx in range(8):
        specs.append(uart_case_diagonal_variant(idx, 6))
    for idx in range(5):
        specs.append(uart_case_real_coupled(idx, 6, 0.10))
    for idx in range(5):
        specs.append(uart_case_complex_coupled(idx, 6, 0.08))
    for idx in range(10):
        specs.append(uart_case_correlated(idx, 12 if idx % 2 else 8))

    snr_cycle = [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20]
    for idx in range(80):
        specs.append(random_rayleigh_case(rng, snr_cycle[idx % len(snr_cycle)], idx + 100))
    return specs


def reindex_vectors(vectors):
    reindexed = []
    for idx, vector in enumerate(vectors):
        item = dict(vector)
        item["vector_idx"] = idx
        reindexed.append(item)
    return reindexed


def select_balanced_extras(base_vectors, candidate_vectors, target_count):
    selected = list(base_vectors)
    coverage = {mode: 0 for mode in MODE_ITERS}
    for vector in selected:
        coverage[int(vector["expected_mode"])] += 1

    by_mode = {mode: [] for mode in MODE_ITERS}
    used_names = {vector["case_name"] for vector in selected}
    for vector in candidate_vectors:
        if vector["case_name"] in used_names:
            continue
        by_mode[int(vector["expected_mode"])].append(vector)

    while len(selected) < target_count and any(by_mode.values()):
        available_modes = [mode for mode in MODE_ITERS if by_mode[mode]]
        mode = min(available_modes, key=lambda item: (coverage[item], item))
        vector = by_mode[mode].pop(0)
        selected.append(vector)
        coverage[mode] += 1

    return reindex_vectors(selected[:target_count])


def build_uart_profile_vectors(num_vectors, seed):
    base_rng = np.random.default_rng(seed)
    base_specs = build_case_specs(min(20, num_vectors), base_rng)
    base_vectors = [
        generate_vector(spec, base_rng, idx)
        for idx, spec in enumerate(base_specs)
    ]
    if num_vectors <= len(base_vectors):
        return reindex_vectors(base_vectors[:num_vectors])

    extra_spec_rng = np.random.default_rng(seed + 9000)
    extra_specs = build_uart_extra_case_specs(extra_spec_rng)
    extra_vector_rng = np.random.default_rng(seed + 9001)
    extra_vectors = [
        generate_vector(spec, extra_vector_rng, len(base_vectors) + idx)
        for idx, spec in enumerate(extra_specs)
    ]
    return select_balanced_extras(base_vectors, extra_vectors, num_vectors)


def generate_vector(spec, rng, vector_idx):
    bits_tx = np.asarray(spec["bits_tx"], dtype=np.int8)
    symbols = qpsk_mod(bits_tx)
    y_clean = spec["H"] @ symbols
    y, noise_var = add_awgn(
        rng, y_clean, spec["snr_db"], noise_var_override=spec["noise_var_override"]
    )

    H_re = quantize_to_int(np.real(spec["H"]), H_W, H_FRAC)
    H_im = quantize_to_int(np.imag(spec["H"]), H_W, H_FRAC)
    y_re = quantize_to_int(np.real(y), Y_W, Y_FRAC)
    y_im = quantize_to_int(np.imag(y), Y_W, Y_FRAC)
    noise_var_int = int(quantize_to_int(noise_var, GBW_W, GBW_FRAC))

    G_re, G_im = rtl_gram_matrix(H_re, H_im)
    b_re, b_im = rtl_matched_filter(H_re, H_im, y_re, y_im)
    W_re, W_im = rtl_regularize(G_re, G_im, noise_var_int)
    diag_sum, offdiag_sum = rtl_condition_metric(G_re, G_im)
    snr_level = snr_to_level(spec["snr_db"])
    expected_mode, expected_num_iters = rtl_select_mode(snr_level, diag_sum, offdiag_sum)
    x_re, x_im = rtl_gs_solver(W_re, W_im, b_re, b_im, expected_num_iters)
    xout_re = rtl_x_to_xout(x_re)
    xout_im = rtl_x_to_xout(x_im)
    expected_bits = rtl_slice_bits(xout_re, xout_im)

    return {
        "vector_idx": vector_idx,
        "case_name": spec["case_name"],
        "snr_db": spec["snr_db"],
        "snr_level": snr_level,
        "noise_var_float": float(noise_var),
        "noise_var_int": noise_var_int,
        "bits_tx": bits_tx.astype(int).tolist(),
        "qpsk_symbols": complex_to_pairs(symbols),
        "H_float": complex_to_pairs(spec["H"]),
        "y_float": complex_to_pairs(y),
        "H_re": H_re.astype(int).tolist(),
        "H_im": H_im.astype(int).tolist(),
        "y_re": y_re.astype(int).tolist(),
        "y_im": y_im.astype(int).tolist(),
        "G_re": G_re.astype(int).tolist(),
        "G_im": G_im.astype(int).tolist(),
        "b_re": b_re.astype(int).tolist(),
        "b_im": b_im.astype(int).tolist(),
        "W_re": W_re.astype(int).tolist(),
        "W_im": W_im.astype(int).tolist(),
        "diag_sum": int(diag_sum),
        "offdiag_sum": int(offdiag_sum),
        "expected_mode": int(expected_mode),
        "expected_num_iters": int(expected_num_iters),
        "x_re": x_re.astype(int).tolist(),
        "x_im": x_im.astype(int).tolist(),
        "expected_xout_re": xout_re.astype(int).tolist(),
        "expected_xout_im": xout_im.astype(int).tolist(),
        "expected_bits": [int(value) for value in expected_bits],
    }


def sv_signed(value, width):
    value = int(value)
    if value < 0:
        return f"-{width}'sd{abs(value)}"
    return f"{width}'sd{value}"


def sv_unsigned(value, width):
    return f"{width}'d{int(value)}"


def sv_bits(value):
    return f"2'b{int(value):02b}"


def sv_1d(values, fmt):
    return "'{" + ", ".join(fmt(value) for value in values) + "}"


def sv_2d(values, fmt, indent):
    pad = " " * indent
    rows = [pad + "    " + sv_1d(row, fmt) for row in values]
    return "'{\n" + ",\n".join(rows) + "\n" + pad + "}"


def sv_3d(values, fmt, indent):
    pad = " " * indent
    blocks = [pad + "    " + sv_2d(block, fmt, indent + 4) for block in values]
    return "'{\n" + ",\n".join(blocks) + "\n" + pad + "}"


def write_sv_package(vectors, output_path):
    output_path.parent.mkdir(parents=True, exist_ok=True)
    h_re = [v["H_re"] for v in vectors]
    h_im = [v["H_im"] for v in vectors]
    y_re = [v["y_re"] for v in vectors]
    y_im = [v["y_im"] for v in vectors]
    xout_re = [v["expected_xout_re"] for v in vectors]
    xout_im = [v["expected_xout_im"] for v in vectors]
    bits = [v["expected_bits"] for v in vectors]

    lines = [
        "package phase6_vectors_pkg;",
        "  import fixed_point_pkg::*;",
        "",
        f"  parameter int NUM_PHASE6_VECTORS = {len(vectors)};",
        "",
        "  localparam logic [1:0] V_SNR_LEVEL [NUM_PHASE6_VECTORS] = "
        + sv_1d([v["snr_level"] for v in vectors], lambda x: sv_unsigned(x, 2))
        + ";",
        "  localparam logic signed [GBW_W-1:0] V_NOISE_VAR [NUM_PHASE6_VECTORS] = "
        + sv_1d([v["noise_var_int"] for v in vectors], lambda x: sv_signed(x, GBW_W))
        + ";",
        "",
        "  localparam logic signed [H_W-1:0] V_H_RE [NUM_PHASE6_VECTORS][NR][NT] = "
        + sv_3d(h_re, lambda x: sv_signed(x, H_W), 2)
        + ";",
        "  localparam logic signed [H_W-1:0] V_H_IM [NUM_PHASE6_VECTORS][NR][NT] = "
        + sv_3d(h_im, lambda x: sv_signed(x, H_W), 2)
        + ";",
        "",
        "  localparam logic signed [Y_W-1:0] V_Y_RE [NUM_PHASE6_VECTORS][NR] = "
        + sv_2d(y_re, lambda x: sv_signed(x, Y_W), 2)
        + ";",
        "  localparam logic signed [Y_W-1:0] V_Y_IM [NUM_PHASE6_VECTORS][NR] = "
        + sv_2d(y_im, lambda x: sv_signed(x, Y_W), 2)
        + ";",
        "",
        "  localparam logic [1:0] V_EXP_MODE [NUM_PHASE6_VECTORS] = "
        + sv_1d([v["expected_mode"] for v in vectors], lambda x: sv_unsigned(x, 2))
        + ";",
        "  localparam logic [4:0] V_EXP_NUM_ITERS [NUM_PHASE6_VECTORS] = "
        + sv_1d([v["expected_num_iters"] for v in vectors], lambda x: sv_unsigned(x, 5))
        + ";",
        "",
        "  localparam logic signed [XOUT_W-1:0] V_EXP_XOUT_RE [NUM_PHASE6_VECTORS][NT] = "
        + sv_2d(xout_re, lambda x: sv_signed(x, XOUT_W), 2)
        + ";",
        "  localparam logic signed [XOUT_W-1:0] V_EXP_XOUT_IM [NUM_PHASE6_VECTORS][NT] = "
        + sv_2d(xout_im, lambda x: sv_signed(x, XOUT_W), 2)
        + ";",
        "",
        "  localparam logic [1:0] V_EXP_BITS [NUM_PHASE6_VECTORS][NT] = "
        + sv_2d(bits, sv_bits, 2)
        + ";",
        "",
        "endpackage",
        "",
    ]
    output_path.write_text("\n".join(lines), encoding="utf-8")


def write_json_summary(vectors, output_path):
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(vectors, indent=2), encoding="utf-8")


def parse_args():
    parser = ArgumentParser(description="Export Phase 6 RTL-equivalence vectors")
    parser.add_argument("--num-vectors", type=int, default=20)
    parser.add_argument("--seed", type=int, default=123)
    parser.add_argument(
        "--sv-output",
        type=Path,
        default=PROJECT_ROOT / "tb" / "phase6_vectors_pkg.sv",
    )
    parser.add_argument(
        "--json-output",
        type=Path,
        default=PROJECT_ROOT / "vectors" / "phase6_rtl_vectors" / "phase6_vectors_summary.json",
    )
    parser.add_argument(
        "--skip-sv",
        action="store_true",
        help="Write only the JSON summary and leave the SystemVerilog package untouched",
    )
    parser.add_argument(
        "--profile",
        choices=("default", "uart"),
        default="default",
        help="Vector generation profile; 'uart' preserves the 20-vector base and adds balanced UART extras",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    if args.profile == "uart":
        vectors = build_uart_profile_vectors(args.num_vectors, args.seed)
    else:
        rng = np.random.default_rng(args.seed)
        specs = build_case_specs(args.num_vectors, rng)
        vectors = [generate_vector(spec, rng, idx) for idx, spec in enumerate(specs)]
    if not args.skip_sv:
        write_sv_package(vectors, args.sv_output)
    write_json_summary(vectors, args.json_output)
    print(f"Generated {len(vectors)} Phase 6 RTL-equivalence vectors")
    if args.skip_sv:
        print("SV package: skipped")
    else:
        print(f"SV package: {args.sv_output}")
    print(f"JSON summary: {args.json_output}")


if __name__ == "__main__":
    main()
