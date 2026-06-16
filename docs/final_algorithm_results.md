# Final Algorithm Results

## Purpose

This document records algorithm-level BER and adaptive-iteration results for the 4x4 QPSK adaptive fixed-point Gauss-Seidel MIMO detector. These results complement RTL verification and ZedBoard UART hardware validation.

## Simulation Setup

- MIMO configuration: 4x4
- Modulation: QPSK with mapping `+re +im -> 00`, `-re +im -> 01`, `-re -im -> 11`, `+re -im -> 10`
- Channel: flat Rayleigh fading
- Noise: complex AWGN
- SNR list: `0,2,4,6,8,10,12,14,16,18,20` dB
- Frames per SNR: 1000
- Random seed: 12345
- Detectors compared: ZF, MMSE, GS-4, GS-8, GS-16, adaptive GS hardware policy
- Adaptive GS hardware policy: GS-4 when `snr_level >= 2` and `100*diag_sum >= 105*offdiag_sum`; GS-8 when `snr_level >= 1` and `100*diag_sum >= 80*offdiag_sum`; otherwise GS-16
- Fixed-point formats: H/y Q4.12, G/b/W Q8.12, ACC Q12.16, x Q6.16, xout Q4.12
- Runtime for this run: 177.2 seconds

## Plot Outputs

- `results/final_algorithm_plots/ber_vs_snr.png`
- `results/final_algorithm_plots/adaptive_avg_iters_vs_snr.png`
- `results/final_algorithm_plots/adaptive_mode_distribution_vs_snr.png`
- `results/final_algorithm_plots/adaptive_iteration_saving_vs_snr.png`
- `results/final_algorithm_plots/fixed_vs_float_ber.png`

## BER vs SNR

| SNR dB | ZF | MMSE | GS-4 | GS-8 | GS-16 | Adaptive GS hardware policy |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 2.1125e-01 | 1.0437e-01 | 1.0537e-01 | 1.0475e-01 | 1.0462e-01 | 1.0462e-01 |
| 2 | 1.6662e-01 | 7.5375e-02 | 8.2500e-02 | 7.5750e-02 | 7.5375e-02 | 7.5375e-02 |
| 4 | 1.3087e-01 | 5.4500e-02 | 6.9250e-02 | 5.7625e-02 | 5.4750e-02 | 5.5000e-02 |
| 6 | 9.0125e-02 | 3.5625e-02 | 5.6375e-02 | 3.9250e-02 | 3.6625e-02 | 3.6500e-02 |
| 8 | 6.2375e-02 | 2.8000e-02 | 6.4750e-02 | 3.9125e-02 | 3.1875e-02 | 3.3000e-02 |
| 10 | 4.2500e-02 | 1.5000e-02 | 5.4250e-02 | 2.9875e-02 | 1.8875e-02 | 1.9375e-02 |
| 12 | 2.5625e-02 | 7.8750e-03 | 5.3000e-02 | 2.9000e-02 | 1.4875e-02 | 1.5375e-02 |
| 14 | 1.8250e-02 | 5.3750e-03 | 5.9375e-02 | 3.1250e-02 | 1.6875e-02 | 1.7750e-02 |
| 16 | 9.5000e-03 | 3.3750e-03 | 6.2000e-02 | 3.5375e-02 | 1.7375e-02 | 1.8000e-02 |
| 18 | 8.7500e-03 | 3.1250e-03 | 6.4125e-02 | 3.5000e-02 | 1.7500e-02 | 1.8375e-02 |
| 20 | 4.5000e-03 | 2.0000e-03 | 5.9000e-02 | 3.3250e-02 | 1.7875e-02 | 1.8625e-02 |

### Inference

MMSE is the exact regularized linear solve for this model and improves with SNR. GS-4, GS-8, and GS-16 are finite-iteration approximations to the same solve, so they can show a BER floor on random square 4x4 Rayleigh channels when the system is weakly diagonally dominant or ill-conditioned. The `--diagnose-gs` mode checks one deterministic frame and confirms that the GS residual and solution error decrease as iteration count increases. ZF can be worse, especially at lower SNR, because it does not regularize noise enhancement.

## Adaptive Average Iterations

| SNR dB | Avg iterations | Saving vs GS-16 (%) |
| --- | --- | --- |
| 0 | 16.00 | 0.00 |
| 2 | 16.00 | 0.00 |
| 4 | 15.10 | 5.65 |
| 6 | 15.18 | 5.15 |
| 8 | 15.12 | 5.53 |
| 10 | 15.11 | 5.55 |
| 12 | 15.24 | 4.75 |
| 14 | 14.93 | 6.70 |
| 16 | 15.23 | 4.83 |
| 18 | 15.09 | 5.67 |
| 20 | 15.14 | 5.37 |

### Inference

Lower average iteration count means reduced compute work compared with always using GS-16. The hardware policy used here is conservative: it selects fewer iterations only when the SNR and diagonal-dominance metric indicate an easier solve, and it otherwise stays at GS-16. On random 4x4 Rayleigh channels this often produces average iterations close to 16, so low savings are expected rather than evidence of a fixed-point or BER accounting bug.

## Mode Distribution

| SNR dB | GS-4 % | GS-8 % | GS-16 % |
| --- | --- | --- | --- |
| 0 | 0.00 | 0.00 | 100.00 |
| 2 | 0.00 | 0.00 | 100.00 |
| 4 | 0.00 | 11.30 | 88.70 |
| 6 | 0.00 | 10.30 | 89.70 |
| 8 | 0.70 | 10.00 | 89.30 |
| 10 | 1.60 | 8.70 | 89.70 |
| 12 | 0.60 | 8.60 | 90.80 |
| 14 | 1.60 | 11.00 | 87.40 |
| 16 | 0.90 | 8.30 | 90.80 |
| 18 | 0.70 | 10.30 | 89.00 |
| 20 | 0.70 | 9.70 | 89.60 |

### Inference

GS-4 is selected for easier high-SNR and more diagonally dominant cases. GS-16 is selected for lower-SNR or weak-dominance cases where more iterations are needed. GS-8 occupies the intermediate policy region. If this table is dominated by GS-16, the policy is acting conservatively for the channel ensemble.

## Iteration Saving

| SNR dB | Avg iterations | Saving (%) |
| --- | --- | --- |
| 0 | 16.00 | 0.00 |
| 2 | 16.00 | 0.00 |
| 4 | 15.10 | 5.65 |
| 6 | 15.18 | 5.15 |
| 8 | 15.12 | 5.53 |
| 10 | 15.11 | 5.55 |
| 12 | 15.24 | 4.75 |
| 14 | 14.93 | 6.70 |
| 16 | 15.23 | 4.83 |
| 18 | 15.09 | 5.67 |
| 20 | 15.14 | 5.37 |

### Inference

The saving metric is `(16 - avg_iters) / 16 * 100%`. It quantifies the adaptive-computation benefit relative to always running GS-16. Low values mean the hardware-consistent policy is choosing robustness over iteration reduction for these frames.

## Fixed-Point vs Floating-Point

| SNR dB | Float adaptive | Fixed adaptive | Adaptive gap | Float GS-16 | Fixed GS-16 | GS-16 gap |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 1.0462e-01 | 1.0462e-01 | 0.0000e+00 | 1.0462e-01 | 1.0462e-01 | 0.0000e+00 |
| 2 | 7.5375e-02 | 7.5500e-02 | 1.2500e-04 | 7.5375e-02 | 7.5500e-02 | 1.2500e-04 |
| 4 | 5.5000e-02 | 5.5000e-02 | 0.0000e+00 | 5.4750e-02 | 5.4750e-02 | 0.0000e+00 |
| 6 | 3.6500e-02 | 3.6500e-02 | 0.0000e+00 | 3.6625e-02 | 3.6625e-02 | 0.0000e+00 |
| 8 | 3.3000e-02 | 3.2625e-02 | -3.7500e-04 | 3.1875e-02 | 3.1500e-02 | -3.7500e-04 |
| 10 | 1.9375e-02 | 1.9375e-02 | 0.0000e+00 | 1.8875e-02 | 1.8875e-02 | 0.0000e+00 |
| 12 | 1.5375e-02 | 1.5625e-02 | 2.5000e-04 | 1.4875e-02 | 1.5125e-02 | 2.5000e-04 |
| 14 | 1.7750e-02 | 1.7750e-02 | 0.0000e+00 | 1.6875e-02 | 1.6875e-02 | 0.0000e+00 |
| 16 | 1.8000e-02 | 1.8000e-02 | 0.0000e+00 | 1.7375e-02 | 1.7375e-02 | 0.0000e+00 |
| 18 | 1.8375e-02 | 1.8500e-02 | 1.2500e-04 | 1.7500e-02 | 1.7625e-02 | 1.2500e-04 |
| 20 | 1.8625e-02 | 1.8625e-02 | 0.0000e+00 | 1.7875e-02 | 1.7875e-02 | 0.0000e+00 |

### Inference

The fixed-point adaptive GS curve should stay close to floating-point adaptive GS if the selected Q formats are adequate. Any visible gap is reported directly in the table rather than hidden or rounded away.

## Paper-Ready Summary

The algorithm-level results are valid for the current hardware policy, but they should be interpreted as a conservative adaptive-GS configuration. The diagnostic confirms that the GS update, diagonal initialization, MMSE matrix construction, noise convention, and QPSK bit mapping are internally consistent. The BER floors and low iteration savings in the quick random-Rayleigh run are therefore best explained by finite GS iteration count plus conservative adaptive thresholds, not by an RTL or Python bit-ordering bug. Together with the RTL and ZedBoard UART hardware regression results, these plots support FPGA implementability; a separate clearly labeled software policy sweep would be needed to claim larger adaptive iteration savings.


## Adaptive Policy Sweep

The implemented FPGA hardware uses the hardware-consistent conservative policy labeled `Adaptive GS hardware policy`. That policy was validated on ZedBoard, but it gives low average iteration savings in random 4x4 Rayleigh simulations because it selects GS-16 for most weak-dominance cases.

The additional `balanced`, `aggressive`, and `aggressive_v2` curves are software-only Phase 2 policy studies. They reuse the policy thresholds from `python/phase2_adaptive_float_4x4.py` and use the Phase 2 complex-magnitude dominance metric. These policies are not currently implemented in the FPGA bitstream unless the RTL is explicitly changed and revalidated.

### Policy Sweep Outputs

- `results/final_algorithm_plots/adaptive_policy_sweep.csv`
- `results/final_algorithm_plots/adaptive_policy_summary.json`
- `results/final_algorithm_plots/adaptive_policy_ber_vs_snr.png`
- `results/final_algorithm_plots/adaptive_policy_avg_iters_vs_snr.png`
- `results/final_algorithm_plots/adaptive_policy_iteration_saving_vs_snr.png`
- `results/final_algorithm_plots/adaptive_policy_mode_distribution_hardware.png`
- `results/final_algorithm_plots/adaptive_policy_mode_distribution_balanced.png`
- `results/final_algorithm_plots/adaptive_policy_mode_distribution_aggressive.png`
- `results/final_algorithm_plots/adaptive_policy_mode_distribution_aggressive_v2.png`

| Policy | Mean avg iterations | Mean saving vs GS-16 (%) | Max BER gap vs GS-16 | BER at 20 dB | Interpretation |
| --- | --- | --- | --- | --- | --- |
| Adaptive GS hardware policy | 15.28 | 4.47 | 1.1250e-03 | 1.8625e-02 | conservative/accurate |
| Adaptive GS balanced | 14.99 | 6.33 | 1.2500e-03 | 1.8500e-02 | balanced tradeoff |
| Adaptive GS aggressive | 12.81 | 19.96 | 6.0000e-03 | 2.2875e-02 | aggressive/high-saving |
| Adaptive GS aggressive_v2 | 11.53 | 27.91 | 1.0000e-02 | 2.6250e-02 | aggressive/high-saving |

### Inference

If the balanced or aggressive software policies give much higher savings with an acceptable BER gap, they can be proposed as future hardware policy options. If their BER gap is too large for the target system, the hardware policy should remain as implemented and the paper should state that adaptive savings are modest for this random 4x4 Rayleigh setting. Do not claim the FPGA implements the balanced or aggressive policies unless the RTL is changed and the ZedBoard validation is repeated.
