# FPGA Implementation of an Adaptive Fixed-Point Gauss-Seidel Detector for 4x4 QPSK MIMO Systems

This repository implements and validates a 4x4 QPSK MIMO detector using adaptive fixed-point Gauss-Seidel (GS) iterations on FPGA. The detector avoids explicit matrix inversion by solving an MMSE-style linear system iteratively, then slices the estimated symbols back to QPSK bits.

The project covers the full path from Python algorithm modeling to fixed-point conversion, RTL implementation, FPGA synthesis/implementation, physical ZedBoard UART validation, and detector latency analysis. The final hardware target is the ZedBoard Zynq-7000 board using part `xc7z020clg484-1`.

## Project Overview

For a received MIMO vector `y`, channel matrix `H`, and noise variance `noise_var`, the detector computes:

- `G = H^H H`
- `b = H^H y`
- `W = G + noise_var I`
- solves `W x_hat = b` using fixed-point GS iterations
- slices `x_hat` into QPSK bits

The implemented adaptive detector selects among:

- mode 0: GS-4
- mode 1: GS-8
- mode 2: GS-16

UART is used only as a board validation and host-control interface. This repository does not claim real RF input, over-the-air testing, or measured wireless link throughput.

## Key Contributions

- Python floating-point and fixed-point MIMO detection flow.
- Adaptive GS mode selection among GS-4, GS-8, and GS-16.
- Fixed-point Q-format design for channel, Gram matrix, matched filter, solver, and output stages.
- Baseline unrolled RTL and optimized sequential resource-shared RTL.
- Timing-clean ZedBoard implementation for the UART-controlled sequential detector.
- PC-driven UART hardware regression using fixed-point golden vectors.
- 50-vector physical ZedBoard validation with exact golden-model match.
- Detector-only latency and throughput measurement from RTL simulation cycle counts.

## System Flow

```text
Python golden model
    |
fixed-point vectors
    |
UART packet from PC
    |
CP2102 USB-UART
    |
ZedBoard JA Pmod
    |
FPGA UART RX + protocol parser
    |
sequential adaptive GS detector
    |
QPSK slicer
    |
UART TX response
    |
Python PASS/FAIL checker
```

The UART path makes the FPGA easy to exercise from a PC, but it is not the MIMO RF datapath. Detector latency and throughput are reported separately from UART transfer time.

## Algorithm

The received signal model is:

```text
y = Hx + n
```

The detector forms the regularized normal equation:

```text
G = H^H H
b = H^H y
W = G + noise_var I
W x_hat = b
```

The complex GS update is:

```text
x_i = (b_i - sum_{j<i} W_ij x_j_new - sum_{j>i} W_ij x_j_old) / W_ii
```

The hardware adaptive policy is:

```text
if snr_level >= 2 and 100*diag_sum >= 105*offdiag_sum:
    mode = GS-4
elif snr_level >= 1 and 100*diag_sum >= 80*offdiag_sum:
    mode = GS-8
else:
    mode = GS-16
```

QPSK bit mapping:

| Symbol quadrant | Bits |
| --- | --- |
| `+re +im` | `00` |
| `-re +im` | `01` |
| `-re -im` | `11` |
| `+re -im` | `10` |

## Fixed-Point Design

| Signal | Format | Width | Purpose |
| ------ | -----: | ----: | ------- |
| H/y | Q4.12 | 16-bit signed | Input channel and received-vector precision |
| G/b/W | Q8.12 | 20-bit signed | Gram matrix, matched-filter, and regularized-system dynamic range |
| ACC | Q12.16 | 28-bit signed | Complex multiply-accumulate margin |
| x | Q6.16 | 22-bit signed | Internal GS solution estimate |
| xout | Q4.12 | 16-bit signed | Detector output and slicer interface |

Wider internal formats reduce overflow risk during Gram matrix generation, matched filtering, regularization, and iterative solving. Q4.12 maps `+1.0` to `4096` and `-1.0` to `-4096`, matching the fixed-point QPSK output checks.

## RTL Architecture

Main sequential detector blocks:

- `gram_matrix_seq`: computes `G = H^H H`
- `matched_filter_seq`: computes `b = H^H y`
- `regularization_metric_seq`: computes `W = G + noise_var I` and the diagonal/off-diagonal metric
- `mode_select_unit`: chooses GS-4, GS-8, or GS-16
- `gs_solver_seq`: sequential fixed-point GS solver
- `signed_divider_seq`: multi-cycle signed divider used by the GS solver
- `x_to_xout_converter`: converts internal Q6.16 solver output to Q4.12
- `qpsk_slicer_array`: converts signs of `xout` into QPSK bits
- `mimo_detector_top_seq`: top-level sequential detector

UART board-validation blocks:

- `uart_rx`
- `uart_tx`
- `uart_mimo_protocol`
- `zedboard_mimo_uart_top`

The sequential architecture reuses arithmetic resources over multiple cycles. This is the key architectural step that reduced LUT/DSP pressure compared with the unrolled baseline while preserving exact fixed-point golden-vector behavior.

## Difference Between rtl/ and rtl_seq/

| Directory | Purpose | Status |
| --------- | ------- | ------ |
| `rtl/` | Baseline/unrolled detector RTL | Functional reference; not FPGA-feasible on target |
| `rtl_seq/` | Sequential resource-shared detector RTL | Timing-clean, hardware-validated implementation |

`rtl/` contains the earlier baseline/unrolled RTL. It was useful for functional bring-up and reference testing, but synthesis/implementation showed very high LUT use and severe negative timing.

`rtl_seq/` contains the optimized sequential/resource-shared RTL. It reuses arithmetic blocks over multiple cycles and includes the sequential Gram matrix, matched filter, regularization/metric, GS solver, UART protocol path, and ZedBoard top. This is the main RTL path for synthesis, implementation, and hardware validation.

## FPGA Implementation Results

| Architecture | LUTs | FFs | DSPs | BRAM | WNS | Result |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Unrolled baseline | ~116,619 | Not reported | 90 | Not reported | -189.965 ns | Failed placement / infeasible |
| Sequential resource-shared RTL | ~2,962 | ~2,289 | 12 | 0 | Timing clean | Feasible |
| ZedBoard UART top | 3,322 | 4,102 | 12 | 0 | +3.153 ns | Bitstream generated and hardware-validated |

The ZedBoard UART top was implemented for `xc7z020clg484-1` and generated:

- bitstream: `results/phase9_zedboard_uart/clk_20p000ns/zedboard_mimo_uart_top.bit`
- routed checkpoint: `results/phase9_zedboard_uart/clk_20p000ns/routed_zedboard_uart_demo.dcp`
- post-route estimated total on-chip power: approximately 0.236 W

The main architectural contribution is the move from infeasible unrolled RTL to resource-shared sequential RTL. The UART top adds validation logic but remains small and timing clean.

## UART Hardware Validation

The UART hardware flow lets a PC send fixed-point vectors to the FPGA and compare returned detector outputs against the Python fixed-point golden model.

Hardware setup used for validation:

- Board: ZedBoard / `xc7z020`
- UART adapter: CP2102 / Silicon Labs CP210x USB-UART
- COM port used during validation: `COM5`
- Baud rate: 115200
- FPGA UART pins are on the JA Pmod, not the onboard PS USB-UART MIO path

Physical wiring:

```text
CP2102 TXD -> ZedBoard JA1 / Y11  -> FPGA uart_rx_i
CP2102 RXD -> ZedBoard JA2 / AA11 -> FPGA uart_tx_o
CP2102 GND -> ZedBoard JA Pmod GND
CP2102 3V3 -> not connected
CP2102 +5V -> not connected
```

The hardware response checker compares:

- adaptive mode
- `num_iters`
- detected QPSK bits
- `xout_re`
- `xout_im`

| Test | Vectors | GS-4 | GS-8 | GS-16 | Exact match fields | Result |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| Identity | 1 | 1 | 0 | 0 | bits, xout | PASS |
| Basic regression | 4 | 2 | 1 | 1 | mode, num_iters, bits, xout | PASS |
| Phase6 20 | 20 | 3 | 2 | 15 | mode, num_iters, bits, xout | PASS |
| Phase6 50 | 50 | 17 | 17 | 16 | mode, num_iters, bits, xout | PASS |

The 50-vector regression passed on physical ZedBoard hardware. This validates the programmed FPGA behavior for deterministic fixed-point vectors; it is not a hardware BER or RF-channel measurement.

## Latency and Throughput

Detector latency was measured in RTL simulation from detector `start` accepted to detector `done` asserted. UART transfer time is excluded.

Assumptions:

- detector clock: 50 MHz
- 4 detected QPSK symbols per vector
- 8 detected bits per vector

| Mode | Iterations | Avg cycles/vector | Vectors/s @ 50 MHz | Detected bits/s @ 50 MHz |
| --- | ---: | ---: | ---: | ---: |
| GS-4 | 4 | 2,568 | 19,470.40 | 155,763.24 |
| GS-8 | 8 | 4,524 | 11,052.17 | 88,417.33 |
| GS-16 | 16 | 8,436 | 5,926.98 | 47,415.84 |

GS-4 has the lowest latency, GS-8 is intermediate, and GS-16 has the highest latency. Adaptive mode selection changes compute latency by choosing among these modes.

## Algorithm Results and Policy Sweep

Python generates BER and policy-sweep plots under `results/final_algorithm_plots/`. The FPGA currently implements the hardware policy described above. Additional policies are software-only studies of the accuracy/iteration tradeoff unless the RTL is changed and revalidated.

| Policy | Mean iterations | Mean saving vs GS-16 | Max BER gap vs GS-16 | BER at 20 dB | Status |
| --- | ---: | ---: | ---: | ---: | --- |
| Hardware policy | 15.284 | 4.47% | 1.125e-03 | 1.8625e-02 | Implemented in FPGA |
| Balanced | 14.988 | 6.33% | 1.250e-03 | 1.8500e-02 | Software-only |
| Aggressive | 12.807 | 19.96% | 6.000e-03 | 2.2875e-02 | Software-only |
| Aggressive_v2 | 11.535 | 27.91% | 1.000e-02 | 2.6250e-02 | Software-only |

Only the hardware policy is implemented in the current RTL/bitstream. The balanced and aggressive policies are future-work options unless implemented in RTL and revalidated on hardware.

## Repository Structure

```text
python/       Python floating-point, fixed-point, vector, plot, and UART host flows
rtl/          Baseline/unrolled detector RTL and shared helper blocks
rtl_seq/      Sequential/resource-shared RTL and ZedBoard UART top
tb/           Baseline testbenches and generated Phase 6 vector package
tb_seq/       Sequential RTL, UART, integration, and latency testbenches
sim_seq/      Questa and XSIM scripts for sequential simulations
syn_seq/      Vivado synthesis/implementation flows for sequential and ZedBoard builds
constraints/  FPGA board and timing constraints
vectors/      Generated deterministic fixed-point vector summaries
docs/         Detailed architecture, hardware validation, result, and bring-up notes
results/      Generated Vivado reports, plots, logs, bitstreams, and latency summaries
```

## How to Run

### Python algorithm plots

```powershell
python -m py_compile python\final_algorithm_plots.py
python python\final_algorithm_plots.py --quick
python python\final_algorithm_plots.py --policy-sweep --quick
```

The full 20,000-frame run is intentionally slower and should be run only when final paper-quality plots are needed.

### Sequential RTL simulation

Questa full sequential regression, if Questa is available:

```powershell
vsim -do sim_seq\run_all_seq.do
```

Vivado XSIM detector latency measurement:

```powershell
C:\AMDDesignTools\2025.2.1\Vivado\bin\xtclsh.bat sim_seq\xsim_latency_seq.tcl
```

### ZedBoard UART hardware validation

High-level steps:

1. Program the ZedBoard PL with `results/phase9_zedboard_uart/clk_20p000ns/zedboard_mimo_uart_top.bit`.
2. Connect the CP2102 USB-UART adapter to the JA Pmod pins.
3. Use BTNC/reset as described in the board documentation.
4. Run the UART regression from the PC.

Example command:

```powershell
python python\uart_batch_regression.py --port COM5 --baud 115200 --vector-set phase6_50 --timeout 10
```

The COM port may differ on another machine. See [docs/zedboard_uart_demo.md](docs/zedboard_uart_demo.md) for wiring, programming, and troubleshooting details.

## Paper/Report Results Summary

This project demonstrates an end-to-end FPGA implementation flow for an adaptive fixed-point GS MIMO detector, from algorithm modeling and fixed-point quantization to sequential RTL, FPGA implementation, and physical ZedBoard validation. The final UART-based hardware regression passed 50 deterministic vectors with exact agreement against the Python fixed-point golden model, while the sequential architecture reduced the design from an infeasible unrolled baseline to a timing-clean FPGA implementation.

Detailed result documents:

- [ZedBoard UART demo](docs/zedboard_uart_demo.md)
- [UART hardware regression results](docs/uart_hardware_regression_results.md)
- [Final result tables](docs/final_result_tables.md)
- [Final algorithm results](docs/final_algorithm_results.md)
- [Latency and throughput results](docs/latency_throughput_results.md)

## Limitations and Future Work

Current limitations:

- The current design targets 4x4 QPSK only.
- UART is a validation and host-control interface, not a real RF input path.
- The implemented hardware policy is conservative and gives modest iteration savings on random square 4x4 Rayleigh simulations.
- Balanced and aggressive policies are software-only for now.
- Throughput numbers are detector-only estimates from RTL simulation cycle counts, not measured RF or over-the-air throughput.

Possible future work:

- Implement the balanced or aggressive adaptive policy in RTL and repeat hardware validation.
- Scale to 8x4 or 8x8 MIMO configurations.
- Add higher-order modulation support.
- Improve throughput with partial parallelism or pipelining.
- Compare against additional detector architectures.
- Add a real channel/RF front-end if suitable hardware becomes available.
