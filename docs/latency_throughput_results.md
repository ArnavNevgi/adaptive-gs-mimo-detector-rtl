# Sequential Detector Latency and Throughput Estimate

## Purpose

This document records detector-only latency for the verified sequential adaptive GS MIMO detector. The measurement is intended for reporting the RTL compute latency of `mimo_detector_top_seq`, not UART validation latency.

Machine-readable outputs:

- `results/latency_seq/latency_seq_summary.csv`
- `results/latency_seq/latency_seq_report.txt`

## Measurement Method

The latency simulation uses `tb_seq/tb_mimo_detector_latency_seq.sv` and instantiates the real sequential detector top:

- `rtl_seq/mimo_detector_top_seq.sv`

The testbench drives representative Phase 6 vectors from `tb/phase6_vectors_pkg.sv`, asserts `start`, counts cycles from the start-accepted clock edge until `done` is asserted, and checks:

- selected mode
- selected `num_iters`
- detected QPSK bits
- `xout_re`
- `xout_im`

UART transfer time is not included. UART is only a validation/control interface and includes PC serial overhead plus 115200-baud packet transfer time.

## Clock Frequency

The throughput estimates assume a 50 MHz detector clock:

- clock period: 20 ns
- detected symbols per vector: 4
- detected bits per vector: 8

## Cycle-Count Table

| Vector | Mode | Iterations | Cycles start-to-done | Latency at 50 MHz | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| identity_gs4 | 0 / GS-4 | 4 | 2568 | 51.36 us | PASS |
| phase6_real_nondiagonal_gs4 | 0 / GS-4 | 4 | 2568 | 51.36 us | PASS |
| phase6_complex_noise_gs8 | 1 / GS-8 | 8 | 4524 | 90.48 us | PASS |
| phase6_random_rayleigh_8db_gs8 | 1 / GS-8 | 8 | 4524 | 90.48 us | PASS |
| phase6_complex_noise_gs16 | 2 / GS-16 | 16 | 8436 | 168.72 us | PASS |
| phase6_weak_dominance_gs16 | 2 / GS-16 | 16 | 8436 | 168.72 us | PASS |

Summary:

| Statistic | Cycles |
| --- | ---: |
| Minimum | 2568 |
| Maximum | 8436 |
| Average across measured vectors | 5176.00 |
| Average GS-4 | 2568.00 |
| Average GS-8 | 4524.00 |
| Average GS-16 | 8436.00 |

## Throughput Estimate Table

| Mode | Average cycles | Vectors/s at 50 MHz | Detected bits/s at 50 MHz |
| --- | ---: | ---: | ---: |
| 0 / GS-4 | 2568.00 | 19470.40 | 155763.24 |
| 1 / GS-8 | 4524.00 | 11052.17 | 88417.33 |
| 2 / GS-16 | 8436.00 | 5926.98 | 47415.84 |

These are RTL compute-throughput estimates based on cycle count only:

`vectors_per_second = 50_000_000 / cycles_start_to_done`

`detected_bits_per_second = vectors_per_second * 8`

## Inference

GS-4 has the lowest measured detector latency. GS-8 has intermediate latency. GS-16 has the highest latency.

Adaptive mode selection changes compute latency by selecting among these modes. In this measured sequential RTL, the selected representative vectors produced fixed mode-dependent cycle counts: 2568 cycles for GS-4, 4524 cycles for GS-8, and 8436 cycles for GS-16.

UART timing is not included in these detector latency numbers. The UART path is a validation and host-control interface, not the detector compute datapath. These throughput estimates are based on 50 MHz RTL simulation cycle count and should not be described as measured RF throughput or over-the-air throughput.
