# Python Simulation Results and Related Code

## 1. Purpose of This Document

This document records the Python modeling and simulation work used before RTL implementation. Python was used to validate the 4x4 QPSK MIMO detector algorithm, compare detector variants, define adaptive Gauss-Seidel iteration policies, choose fixed-point formats, and generate golden expected outputs for RTL and UART hardware validation.

The Python model is the project reference path. The RTL and FPGA hardware are expected to match the fixed-point Python model, not an idealized floating-point-only model.

## Related Existing Documentation

- [Project README](README.md)
- [Final algorithm results](docs/final_algorithm_results.md)
- [Final result tables](docs/final_result_tables.md)
- [Latency and throughput results](docs/latency_throughput_results.md)
- [UART hardware regression results](docs/uart_hardware_regression_results.md)
- [ZedBoard UART demo](docs/zedboard_uart_demo.md)
- [Phase 8 sequential architecture](docs/phase8_sequential_architecture.md)
- [Step 8 sequential architecture notes](docs/step8_sequential_architecture.md)
- [Area optimization plan](docs/area_optimization_plan.md)
- [FPGA implementation and I/O validation](FPGA_Implementation_and_IO_Validation.md)

## 2. Simulation Flow Overview

The Python simulation flow moved from an ideal floating-point algorithm model toward hardware-matching fixed-point data and golden vectors.

```text
Floating-Point MIMO Model
       |
       v
ZF / MMSE / GS Detector Comparison
       |
       v
Adaptive GS Iteration Policy
       |
       v
Fixed-Point Conversion
       |
       v
BER / Iteration / Mode Distribution Results
       |
       v
Golden Vector Export for RTL and UART Hardware Validation
```

The main scripts are:

- [python/phase1_float_4x4.py](python/phase1_float_4x4.py)
- [python/phase2_adaptive_float_4x4.py](python/phase2_adaptive_float_4x4.py)
- [python/phase3_fixed_point_4x4.py](python/phase3_fixed_point_4x4.py)
- [python/phase4_scaling_fixed_point.py](python/phase4_scaling_fixed_point.py)
- [python/final_algorithm_plots.py](python/final_algorithm_plots.py)
- [python/export_phase6_rtl_vectors.py](python/export_phase6_rtl_vectors.py)

The Python environment dependencies are listed in [python/requirements.txt](python/requirements.txt): `numpy` and `matplotlib`. UART host validation additionally imports `pyserial` at runtime in [python/uart_send_vector.py](python/uart_send_vector.py) and [python/uart_batch_regression.py](python/uart_batch_regression.py).

## 3. Floating-Point Baseline Simulation

The initial floating-point model is [python/phase1_float_4x4.py](python/phase1_float_4x4.py). It simulates a 4x4 MIMO system with QPSK modulation.

Confirmed setup from the code:

- `NT = 4`, `NR = 4`
- `NUM_FRAMES = 20_000`
- `SNR_DB_LIST = 0, 2, 4, ..., 20`
- random seed `42`
- QPSK mapping:
  - `00 -> (1 + 1j) / sqrt(2)`
  - `01 -> (-1 + 1j) / sqrt(2)`
  - `11 -> (-1 - 1j) / sqrt(2)`
  - `10 -> (1 - 1j) / sqrt(2)`
- flat Rayleigh channel entries generated as complex Gaussian values divided by `sqrt(2)`
- complex AWGN with `noise_var = 1 / snr_linear`

The detectors compared in Phase 1 are:

- ZF
- MMSE
- GS-1
- GS-2
- GS-4
- GS-8
- GS-16

The checked-in Phase 1 plot is [results/phase1_float/phase1_ber_4x4.png](results/phase1_float/phase1_ber_4x4.png).

TODO: No raw Phase 1 console log was found in `results/`. Add one if an archival BER table transcript is required.

## 4. Detector Algorithms Simulated

**ZF detector:** implemented in [python/phase1_float_4x4.py](python/phase1_float_4x4.py) as `np.linalg.pinv(H) @ y`. It estimates symbols using the channel pseudo-inverse. It is simple, but it does not include the MMSE noise regularization term.

**MMSE detector:** implemented by forming `G = H^H H`, `b = H^H y`, and solving `W x = b` where `W = G + noise_var I`. In the Python code this uses `np.linalg.solve(W, b)`. MMSE is the exact regularized linear solve used as the main reference for GS.

**Gauss-Seidel detector:** approximates the MMSE solve iteratively. The code initializes with `x = b / diag(W)` and then performs GS sweeps. Newly updated values are used for lower-index terms and previous-iteration values are used for upper-index terms. Phase 1 tests GS-1, GS-2, GS-4, GS-8, and GS-16; the hardware-oriented flow later keeps GS-4, GS-8, and GS-16.

**Adaptive Gauss-Seidel detector:** chooses among GS-4, GS-8, and GS-16 at runtime. The goal is to reduce average iteration count when the channel/SNR condition looks easy, while falling back to GS-16 for harder cases.

## 5. Adaptive Iteration Policy

Adaptive iteration was introduced to reduce computation compared with always running GS-16. The idea is that easy channels may not need all 16 GS iterations, while harder channels should still use more iterations.

The floating-point policy study is in [python/phase2_adaptive_float_4x4.py](python/phase2_adaptive_float_4x4.py). It uses an SNR threshold plus a channel diagonal-dominance metric computed from `G = H^H H`.

Confirmed adaptive modes:

| Mode | Iterations |
| --- | ---: |
| Mode 0 | GS-4 |
| Mode 1 | GS-8 |
| Mode 2 | GS-16 |

Phase 2 software policy thresholds:

| Policy | Easy condition | Medium condition |
| --- | --- | --- |
| conservative | SNR >= 12 dB and dominance >= 1.8 | SNR >= 6 dB and dominance >= 1.2 |
| balanced | SNR >= 10 dB and dominance >= 1.25 | SNR >= 6 dB and dominance >= 0.95 |
| aggressive | SNR >= 8 dB and dominance >= 1.05 | SNR >= 4 dB and dominance >= 0.80 |
| aggressive_v2 | SNR >= 10 dB and dominance >= 0.90 | SNR >= 4 dB and dominance >= 0.75 |

The final hardware-consistent policy is implemented in [python/final_algorithm_plots.py](python/final_algorithm_plots.py) and mirrored in [python/export_phase6_rtl_vectors.py](python/export_phase6_rtl_vectors.py). It uses an RTL-friendly cross-multiply form:

```text
if snr_level >= 2 and 100*diag_sum >= 105*offdiag_sum:
    mode = GS-4
elif snr_level >= 1 and 100*diag_sum >= 80*offdiag_sum:
    mode = GS-8
else:
    mode = GS-16
```

In the final plotting script, the hardware policy metric is the L1-style `abs(real) + abs(imag)` magnitude on `G`, using the same cross-multiply threshold form used by the RTL.

## 6. Fixed-Point Simulation

Fixed-point simulation was needed because floating-point Python results are not directly hardware-realistic. The RTL uses finite-width signed integer arithmetic, quantization, saturation, intermediate accumulator widths, and fixed output formats. The fixed-point Python model checks whether these implementation choices preserve the algorithm behavior closely enough before writing RTL.

The main fixed-point script is [python/phase3_fixed_point_4x4.py](python/phase3_fixed_point_4x4.py). The scaling study reuses the same style of fixed-point model in [python/phase4_scaling_fixed_point.py](python/phase4_scaling_fixed_point.py). The final report plots are produced by [python/final_algorithm_plots.py](python/final_algorithm_plots.py).

Confirmed fixed-point formats:

| Signal | Format | Width | Purpose |
| --- | --- | ---: | --- |
| `H`, `y` | Q4.12 | 16-bit signed | channel and received-vector inputs |
| `G`, `b`, `W` | Q8.12 | 20-bit signed | Gram matrix, matched filter, regularized system |
| accumulator | Q12.16 | 28-bit signed | complex multiply-accumulate margin |
| internal `x` | Q6.16 | 22-bit signed | GS internal solution estimate |
| `x_out` / `xout` | Q4.12 | 16-bit signed | detector output and slicer input |

The fixed-point code records saturation/overflow counts, NaN/Inf counts, mode mismatch rates, fixed-vs-float BER gaps, and quantization error summaries. Checked-in Phase 3 plots include:

- [results/phase3_fixed_point/phase3_ber_fixed_vs_float_4x4.png](results/phase3_fixed_point/phase3_ber_fixed_vs_float_4x4.png)
- [results/phase3_fixed_point/phase3_adaptive_fixed_gap_4x4.png](results/phase3_fixed_point/phase3_adaptive_fixed_gap_4x4.png)
- [results/phase3_fixed_point/phase3_avg_iters_fixed_vs_float_4x4.png](results/phase3_fixed_point/phase3_avg_iters_fixed_vs_float_4x4.png)
- [results/phase3_fixed_point/phase3_mode_mismatch_4x4.png](results/phase3_fixed_point/phase3_mode_mismatch_4x4.png)
- [results/phase3_fixed_point/phase3_saturation_count_4x4.png](results/phase3_fixed_point/phase3_saturation_count_4x4.png)
- [results/phase3_fixed_point/phase3_format_sweep_summary_4x4.png](results/phase3_fixed_point/phase3_format_sweep_summary_4x4.png)
- [results/phase3_fixed_point/phase3_reciprocal_mode_comparison_4x4.png](results/phase3_fixed_point/phase3_reciprocal_mode_comparison_4x4.png)

The final fixed-vs-float CSV [results/final_algorithm_plots/fixed_float_results.csv](results/final_algorithm_plots/fixed_float_results.csv) reports a maximum absolute adaptive BER gap of `3.75e-4` across the final SNR sweep.

TODO: No raw Phase 3 console log was found in `results/`; only plots and final consolidated CSV/JSON data were found.

## 7. Scaling Simulations

The scaling study is [python/phase4_scaling_fixed_point.py](python/phase4_scaling_fixed_point.py). It tests these MIMO configurations:

- 4x4
- 8x4
- 8x8

The script compares:

- fixed-point adaptive BER trends
- MMSE floating-point reference trends
- average adaptive iterations
- mode distribution
- saturation counts
- fixed-vs-float adaptive BER gap
- mode mismatch and RTL-style selector mismatch checks

Checked-in Phase 4 plots:

- [results/phase4_scaling/phase4_ber_scaling_fixed_4x4_8x4_8x8.png](results/phase4_scaling/phase4_ber_scaling_fixed_4x4_8x4_8x8.png)
- [results/phase4_scaling/phase4_avg_iters_scaling.png](results/phase4_scaling/phase4_avg_iters_scaling.png)
- [results/phase4_scaling/phase4_mode_distribution_scaling.png](results/phase4_scaling/phase4_mode_distribution_scaling.png)
- [results/phase4_scaling/phase4_saturation_scaling.png](results/phase4_scaling/phase4_saturation_scaling.png)
- [results/phase4_scaling/phase4_fixed_float_gap_scaling.png](results/phase4_scaling/phase4_fixed_float_gap_scaling.png)

TODO: No machine-readable Phase 4 CSV/JSON summary was found. The checked-in evidence for Phase 4 is plot-based plus the script itself.

## 8. Final Python Result Plots

### Main final plots and data

| Plot / Result File | What It Shows | Linked File |
| --- | --- | --- |
| BER vs SNR | ZF, MMSE, GS-4, GS-8, GS-16, and adaptive hardware-policy BER | [results/final_algorithm_plots/ber_vs_snr.png](results/final_algorithm_plots/ber_vs_snr.png) |
| Average Iterations | Adaptive hardware-policy average GS iteration count vs SNR | [results/final_algorithm_plots/adaptive_avg_iters_vs_snr.png](results/final_algorithm_plots/adaptive_avg_iters_vs_snr.png) |
| Mode Distribution | Hardware-policy GS-4/GS-8/GS-16 mode percentages vs SNR | [results/final_algorithm_plots/adaptive_mode_distribution_vs_snr.png](results/final_algorithm_plots/adaptive_mode_distribution_vs_snr.png) |
| Iteration Saving | Hardware-policy iteration saving relative to fixed GS-16 | [results/final_algorithm_plots/adaptive_iteration_saving_vs_snr.png](results/final_algorithm_plots/adaptive_iteration_saving_vs_snr.png) |
| Fixed vs Float BER | Fixed adaptive and fixed GS-16 BER compared with floating-point versions | [results/final_algorithm_plots/fixed_vs_float_ber.png](results/final_algorithm_plots/fixed_vs_float_ber.png) |
| Algorithm CSV | Machine-readable BER and adaptive iteration table | [results/final_algorithm_plots/algorithm_results.csv](results/final_algorithm_plots/algorithm_results.csv) |
| Algorithm JSON | Metadata and final algorithm result rows | [results/final_algorithm_plots/algorithm_results.json](results/final_algorithm_plots/algorithm_results.json) |
| Mode CSV | Machine-readable hardware-policy mode counts/percentages | [results/final_algorithm_plots/mode_distribution.csv](results/final_algorithm_plots/mode_distribution.csv) |
| Fixed/Float CSV | Machine-readable fixed-vs-float BER and gap data | [results/final_algorithm_plots/fixed_float_results.csv](results/final_algorithm_plots/fixed_float_results.csv) |

### Policy sweep plots and data

| Plot / Result File | What It Shows | Linked File |
| --- | --- | --- |
| Policy BER | Hardware, balanced, aggressive, and aggressive_v2 policy BER vs SNR | [results/final_algorithm_plots/adaptive_policy_ber_vs_snr.png](results/final_algorithm_plots/adaptive_policy_ber_vs_snr.png) |
| Policy Average Iterations | Average iterations for each policy | [results/final_algorithm_plots/adaptive_policy_avg_iters_vs_snr.png](results/final_algorithm_plots/adaptive_policy_avg_iters_vs_snr.png) |
| Policy Saving | Iteration saving for each policy | [results/final_algorithm_plots/adaptive_policy_iteration_saving_vs_snr.png](results/final_algorithm_plots/adaptive_policy_iteration_saving_vs_snr.png) |
| Hardware Policy Modes | Mode distribution for the hardware policy | [results/final_algorithm_plots/adaptive_policy_mode_distribution_hardware.png](results/final_algorithm_plots/adaptive_policy_mode_distribution_hardware.png) |
| Balanced Policy Modes | Mode distribution for the balanced software policy | [results/final_algorithm_plots/adaptive_policy_mode_distribution_balanced.png](results/final_algorithm_plots/adaptive_policy_mode_distribution_balanced.png) |
| Aggressive Policy Modes | Mode distribution for the aggressive software policy | [results/final_algorithm_plots/adaptive_policy_mode_distribution_aggressive.png](results/final_algorithm_plots/adaptive_policy_mode_distribution_aggressive.png) |
| Aggressive_v2 Policy Modes | Mode distribution for the aggressive_v2 software policy | [results/final_algorithm_plots/adaptive_policy_mode_distribution_aggressive_v2.png](results/final_algorithm_plots/adaptive_policy_mode_distribution_aggressive_v2.png) |
| Policy Sweep CSV | Machine-readable per-SNR policy sweep data | [results/final_algorithm_plots/adaptive_policy_sweep.csv](results/final_algorithm_plots/adaptive_policy_sweep.csv) |
| Policy Summary JSON | Machine-readable policy metadata and summary | [results/final_algorithm_plots/adaptive_policy_summary.json](results/final_algorithm_plots/adaptive_policy_summary.json) |

### Earlier phase plots

| Plot / Result File | What It Shows | Linked File |
| --- | --- | --- |
| Phase 1 BER | Floating-point ZF/MMSE/GS comparison | [results/phase1_float/phase1_ber_4x4.png](results/phase1_float/phase1_ber_4x4.png) |
| Phase 2 adaptive BER | Early adaptive BER plot | [results/phase2_adaptive/phase2_adaptive_ber_4x4.png](results/phase2_adaptive/phase2_adaptive_ber_4x4.png) |
| Phase 2 average iterations | Early adaptive average iterations | [results/phase2_adaptive/phase2_avg_iters_4x4.png](results/phase2_adaptive/phase2_avg_iters_4x4.png) |
| Phase 2 policy average iterations | Policy comparison for average iterations | [results/phase2_adaptive/phase2_avg_iters_policy_comparison_4x4.png](results/phase2_adaptive/phase2_avg_iters_policy_comparison_4x4.png) |
| Phase 2 conservative BER | Conservative policy BER | [results/phase2_adaptive/phase2_ber_conservative_4x4.png](results/phase2_adaptive/phase2_ber_conservative_4x4.png) |
| Phase 2 balanced BER | Balanced policy BER | [results/phase2_adaptive/phase2_ber_balanced_4x4.png](results/phase2_adaptive/phase2_ber_balanced_4x4.png) |
| Phase 2 aggressive BER | Aggressive policy BER | [results/phase2_adaptive/phase2_ber_aggressive_4x4.png](results/phase2_adaptive/phase2_ber_aggressive_4x4.png) |
| Phase 2 aggressive_v2 BER | Aggressive_v2 policy BER | [results/phase2_adaptive/phase2_ber_aggressive_v2_4x4.png](results/phase2_adaptive/phase2_ber_aggressive_v2_4x4.png) |
| Phase 2 mode distribution | Early adaptive mode distribution | [results/phase2_adaptive/phase2_mode_distribution_4x4.png](results/phase2_adaptive/phase2_mode_distribution_4x4.png) |
| Phase 2 conservative modes | Conservative policy mode distribution | [results/phase2_adaptive/phase2_mode_distribution_conservative_4x4.png](results/phase2_adaptive/phase2_mode_distribution_conservative_4x4.png) |
| Phase 2 balanced modes | Balanced policy mode distribution | [results/phase2_adaptive/phase2_mode_distribution_balanced_4x4.png](results/phase2_adaptive/phase2_mode_distribution_balanced_4x4.png) |
| Phase 2 aggressive modes | Aggressive policy mode distribution | [results/phase2_adaptive/phase2_mode_distribution_aggressive_4x4.png](results/phase2_adaptive/phase2_mode_distribution_aggressive_4x4.png) |
| Phase 2 aggressive_v2 modes | Aggressive_v2 policy mode distribution | [results/phase2_adaptive/phase2_mode_distribution_aggressive_v2_4x4.png](results/phase2_adaptive/phase2_mode_distribution_aggressive_v2_4x4.png) |
| Phase 3 fixed vs float BER | Fixed-point BER compared with floating point | [results/phase3_fixed_point/phase3_ber_fixed_vs_float_4x4.png](results/phase3_fixed_point/phase3_ber_fixed_vs_float_4x4.png) |
| Phase 3 adaptive gap | Fixed-vs-float adaptive BER gap | [results/phase3_fixed_point/phase3_adaptive_fixed_gap_4x4.png](results/phase3_fixed_point/phase3_adaptive_fixed_gap_4x4.png) |
| Phase 3 average iterations | Fixed and float adaptive average iterations | [results/phase3_fixed_point/phase3_avg_iters_fixed_vs_float_4x4.png](results/phase3_fixed_point/phase3_avg_iters_fixed_vs_float_4x4.png) |
| Phase 3 mode mismatch | Mode mismatch and selector mismatch rates | [results/phase3_fixed_point/phase3_mode_mismatch_4x4.png](results/phase3_fixed_point/phase3_mode_mismatch_4x4.png) |
| Phase 3 saturation | Saturation count vs SNR | [results/phase3_fixed_point/phase3_saturation_count_4x4.png](results/phase3_fixed_point/phase3_saturation_count_4x4.png) |
| Phase 3 format sweep | Q-format profile comparison | [results/phase3_fixed_point/phase3_format_sweep_summary_4x4.png](results/phase3_fixed_point/phase3_format_sweep_summary_4x4.png) |
| Phase 3 reciprocal modes | Reciprocal mode comparison | [results/phase3_fixed_point/phase3_reciprocal_mode_comparison_4x4.png](results/phase3_fixed_point/phase3_reciprocal_mode_comparison_4x4.png) |
| Phase 4 scaling BER | 4x4, 8x4, and 8x8 fixed-point scaling BER | [results/phase4_scaling/phase4_ber_scaling_fixed_4x4_8x4_8x8.png](results/phase4_scaling/phase4_ber_scaling_fixed_4x4_8x4_8x8.png) |
| Phase 4 average iterations | Adaptive iteration scaling across MIMO sizes | [results/phase4_scaling/phase4_avg_iters_scaling.png](results/phase4_scaling/phase4_avg_iters_scaling.png) |
| Phase 4 mode distribution | Average mode distribution across MIMO sizes | [results/phase4_scaling/phase4_mode_distribution_scaling.png](results/phase4_scaling/phase4_mode_distribution_scaling.png) |
| Phase 4 saturation | Saturation behavior across MIMO sizes | [results/phase4_scaling/phase4_saturation_scaling.png](results/phase4_scaling/phase4_saturation_scaling.png) |
| Phase 4 fixed/float gap | Fixed-vs-float adaptive BER gap across MIMO sizes | [results/phase4_scaling/phase4_fixed_float_gap_scaling.png](results/phase4_scaling/phase4_fixed_float_gap_scaling.png) |

## 9. Golden Vector Generation for RTL and FPGA

Python generated deterministic fixed-point vectors for RTL testbenches and UART hardware validation. The main vector export script is [python/export_phase6_rtl_vectors.py](python/export_phase6_rtl_vectors.py).

Generated vector/golden-data files:

- [tb/phase6_vectors_pkg.sv](tb/phase6_vectors_pkg.sv)
- [vectors/phase6_rtl_vectors/phase6_vectors_summary.json](vectors/phase6_rtl_vectors/phase6_vectors_summary.json)
- [vectors/phase6_rtl_vectors/phase6_uart_50_vectors_summary.json](vectors/phase6_rtl_vectors/phase6_uart_50_vectors_summary.json)
- [vectors/phase3_rtl_seed_vectors/](vectors/phase3_rtl_seed_vectors/)

The Phase 6 20-vector JSON contains 20 vectors with mode coverage:

```text
GS-4: 3
GS-8: 2
GS-16: 15
```

The UART 50-vector JSON contains 50 vectors with mode coverage:

```text
GS-4: 17
GS-8: 17
GS-16: 16
```

The UART batch regression script [python/uart_batch_regression.py](python/uart_batch_regression.py) explicitly names these basic regression vectors:

- `identity_gs4`
- `phase6_real_nondiagonal_gs4`
- `phase6_complex_noise_gs8`
- `phase6_complex_noise_gs16`

The identity vector is also built directly in [python/uart_send_vector.py](python/uart_send_vector.py). It uses identity `H`, Q4.12 `y = [+1+j, -1+j, -1-j, +1-j]`, `noise_var = 0`, and expects bits `00 01 11 10`.

RTL and hardware consumers of these golden vectors include:

- [tb/tb_mimo_detector_top_vectors.sv](tb/tb_mimo_detector_top_vectors.sv)
- [tb_seq/tb_mimo_detector_top_seq_vectors.sv](tb_seq/tb_mimo_detector_top_seq_vectors.sv)
- [tb_seq/tb_mimo_detector_latency_seq.sv](tb_seq/tb_mimo_detector_latency_seq.sv)
- [python/uart_batch_regression.py](python/uart_batch_regression.py)
- [python/uart_send_vector.py](python/uart_send_vector.py)

Hardware-validation logs that used Python-generated expected data:

- [results/phase9_zedboard_uart/clk_20p000ns/uart_batch_basic_hw_log.txt](results/phase9_zedboard_uart/clk_20p000ns/uart_batch_basic_hw_log.txt)
- [results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_20_hw_log.txt](results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_20_hw_log.txt)
- [results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_50_hw_log.txt](results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_50_hw_log.txt)
- [results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_50_hw_repeat_log.txt](results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_50_hw_repeat_log.txt)

## 10. Key Numerical Results

| Simulation Stage | Metric | Result |
| --- | --- | --- |
| Final algorithm run | MIMO setup | 4x4 QPSK, flat Rayleigh fading, complex AWGN |
| Final algorithm run | SNR sweep | 0 to 20 dB in 2 dB steps |
| Final algorithm run | Frames per SNR | 1000 |
| Final algorithm run | Random seed | 12345 |
| Floating-point baseline | Detector comparison at 20 dB | ZF `4.5e-3`, MMSE `2.0e-3`, GS-16 `1.7875e-2`, adaptive hardware policy `1.8625e-2` |
| Adaptive hardware policy | Mean average iterations | `15.2844` |
| Adaptive hardware policy | Mean iteration saving vs GS-16 | `4.4727%` |
| Adaptive hardware policy | Average mode split | GS-4 `0.618%`, GS-8 `8.018%`, GS-16 `91.364%` |
| Adaptive hardware policy | Max BER gap vs GS-16 in policy sweep | `1.125e-3` |
| Fixed-point validation | Max absolute adaptive fixed-vs-float BER gap | `3.75e-4` |
| Fixed-point validation | Max absolute GS-16 fixed-vs-float BER gap | `3.75e-4` |
| Policy sweep | Balanced mean saving vs GS-16 | `6.3273%` |
| Policy sweep | Aggressive mean saving vs GS-16 | `19.9591%` |
| Policy sweep | Aggressive_v2 mean saving vs GS-16 | `27.9068%` |
| Phase 6 vector export | Main JSON vector count | 20 vectors |
| Phase 6 UART export | UART JSON vector count | 50 vectors |
| UART hardware validation | 50-vector hardware result | 50/50 PASS in [results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_50_hw_log.txt](results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_50_hw_log.txt) |

The final results above are from [docs/final_algorithm_results.md](docs/final_algorithm_results.md), [results/final_algorithm_plots/algorithm_results.csv](results/final_algorithm_plots/algorithm_results.csv), [results/final_algorithm_plots/fixed_float_results.csv](results/final_algorithm_plots/fixed_float_results.csv), [results/final_algorithm_plots/mode_distribution.csv](results/final_algorithm_plots/mode_distribution.csv), and [results/final_algorithm_plots/adaptive_policy_summary.json](results/final_algorithm_plots/adaptive_policy_summary.json).

## 11. How to Reproduce the Python Results

Run commands from the repository root.

1. Set up Python and install dependencies.

   ```powershell
   python -m pip install -r python/requirements.txt
   ```

2. Run the floating-point baseline simulation.

   ```powershell
   python python/phase1_float_4x4.py
   ```

3. Run the adaptive policy floating-point simulation.

   ```powershell
   python python/phase2_adaptive_float_4x4.py
   ```

4. Run the fixed-point 4x4 simulation.

   ```powershell
   python python/phase3_fixed_point_4x4.py --quick
   ```

   Additional fixed-point experiments supported by the script:

   ```powershell
   python python/phase3_fixed_point_4x4.py --validate
   python python/phase3_fixed_point_4x4.py --format-sweep
   python python/phase3_fixed_point_4x4.py --reciprocal-sweep
   python python/phase3_fixed_point_4x4.py --stress-tests
   python python/phase3_fixed_point_4x4.py --export-rtl-vectors 10
   ```

5. Run the 4x4, 8x4, and 8x8 scaling study.

   ```powershell
   python python/phase4_scaling_fixed_point.py --quick
   ```

   Optional configuration selection:

   ```powershell
   python python/phase4_scaling_fixed_point.py --configs 4x4,8x4,8x8 --validate
   ```

6. Generate final algorithm plots and tables.

   Commands documented in [README.md](README.md):

   ```powershell
   python -m py_compile python/final_algorithm_plots.py
   python python/final_algorithm_plots.py --quick
   python python/final_algorithm_plots.py --policy-sweep --quick
   ```

   The script also supports:

   ```powershell
   python python/final_algorithm_plots.py --diagnose-gs
   python python/final_algorithm_plots.py --frames 1000 --seed 12345 --policy-sweep
   ```

7. Export golden vectors for RTL and UART validation.

   Main 20-vector RTL package/JSON:

   ```powershell
   python python/export_phase6_rtl_vectors.py --num-vectors 20
   ```

   UART-focused 50-vector JSON:

   ```powershell
   python python/export_phase6_rtl_vectors.py --profile uart --num-vectors 50 --json-output vectors/phase6_rtl_vectors/phase6_uart_50_vectors_summary.json --skip-sv
   ```

8. Dry-run UART packet generation and expected-response decode without hardware.

   ```powershell
   python python/uart_send_vector.py --dry-run
   python python/uart_batch_regression.py --dry-run --vector-set phase6_50
   ```

TODO: The Phase 1 through Phase 4 scripts currently define output paths relative to the repository root, while the checked-in plot artifacts are archived under `results/phase*_.../`. Confirm whether the intended reproduction flow includes manually moving plots into those result folders or updating the scripts to write there directly.

## 12. Connection Between Python and RTL

Python was the golden reference model for the project. The RTL implementation was expected to match the fixed-point Python model because that model uses hardware-facing quantization, mode-selection thresholds, and expected fixed-point outputs.

The traceable path is:

```text
Python floating-point model
       |
       v
Python fixed-point model
       |
       v
Phase 6 fixed-point golden vectors
       |
       v
RTL testbench expected values
       |
       v
Sequential RTL regression
       |
       v
UART hardware regression against Python expected outputs
```

The final UART validation used Python host scripts to send fixed-point vectors to the FPGA and then compare the returned `mode`, `num_iters`, `bits`, `xout_re`, and `xout_im` fields against Python-generated expected values. This connected the algorithm model, fixed-point conversion, RTL regression, and programmed FPGA hardware validation into one evidence chain.

## 13. Summary

The Python simulation flow established algorithm correctness, compared detector performance, selected the adaptive GS policy, validated fixed-point formats, produced BER/iteration/mode-distribution results, and generated golden vectors used for RTL and FPGA validation.

The strongest final Python result set is under [results/final_algorithm_plots/](results/final_algorithm_plots/). It records the final 4x4 QPSK SNR sweep, hardware-policy adaptive iteration behavior, fixed-vs-float agreement, and policy-sweep data used to explain why the implemented hardware policy is conservative and why more aggressive policies remain software-only unless the RTL is changed and revalidated.
