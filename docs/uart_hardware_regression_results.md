# UART Hardware Regression Results

## 1. Purpose

This document records physical ZedBoard UART hardware-validation results for the adaptive fixed-point Gauss-Seidel MIMO detector.

The project implements a 4x4 QPSK adaptive fixed-point GS MIMO detector on FPGA. UART is the validation interface only. The PC sends fixed-point `H`, `y`, `noise_var`, and `snr_level` data over UART. The FPGA runs the real sequential detector in PL and returns `mode`, `num_iters`, detected QPSK `bits`, `xout_re`, and `xout_im`. Python compares the FPGA response against fixed-point golden vectors.

These results are fixed-point vector-driven hardware validation over UART. They are not BER measurements, over-the-air MIMO tests, or real RF-input tests.

## 2. Hardware and Bitstream Setup

Board:

```text
ZedBoard, xc7z020
```

Bitstream:

```text
results/phase9_zedboard_uart/clk_20p000ns/zedboard_mimo_uart_top.bit
```

Routed checkpoint:

```text
results/phase9_zedboard_uart/clk_20p000ns/routed_zedboard_uart_demo.dcp
```

UART adapter:

```text
CP2102 / Silicon Labs CP210x USB-UART adapter
COM port: COM5
Baud: 115200
```

Physical wiring:

```text
CP2102 TXD -> ZedBoard JA1 / Y11  -> FPGA uart_rx_i
CP2102 RXD -> ZedBoard JA2 / AA11 -> FPGA uart_tx_o
CP2102 GND -> ZedBoard JA Pmod GND
CP2102 3V3 -> not connected
CP2102 +5V -> not connected
```

Vivado-confirmed UART pins:

```text
uart_rx_i -> Y11,  LVCMOS33
uart_tx_o -> AA11, LVCMOS33
```

FPGA programming note:

```text
Vivado detected: arm_dap_0 xc7z020_1
Selected programmable PL device: xc7z020_1
```

`arm_dap_0` was detected in the hardware chain, but the programmed FPGA/PL device was `xc7z020_1`.

## 3. Validation Method

The validation flow is:

```text
PC Python script
-> CP2102 USB-UART adapter
-> ZedBoard JA Pmod pins
-> FPGA UART RX
-> UART protocol parser
-> sequential adaptive fixed-point GS MIMO detector
-> FPGA UART TX
-> Python response checker
```

For each vector, Python sends a UART `RUN_VECTOR` packet containing fixed-point channel, received-vector, noise, and SNR data. The FPGA response is decoded and compared exactly against the Python fixed-point golden model.

Exact comparison fields:

- `mode`
- `num_iters`
- `bits`
- `xout_re`
- `xout_im`

## 4. Identity-Vector Hardware Result

Command:

```powershell
python python/uart_send_vector.py --port COM5 --baud 115200 --vector identity
```

Output summary:

```text
Status: 0x00 (OK)
Payload length: 22
mode: 0
num_iters: 4
bits: 00 01 11 10
xout_re: [4096, -4096, -4096, 4096]
xout_im: [4096, 4096, -4096, -4096]
PASS: identity vector bits match expected 00 01 11 10
```

Interpretation:

This proves the PC-to-FPGA UART path works for the identity-channel MIMO vector. The FPGA received the vector, ran the sequential adaptive GS detector, selected GS-4, and returned the expected QPSK bits and fixed-point detector outputs.

## 5. 4-Vector Basic Regression Result

Command:

```powershell
python python/uart_batch_regression.py --port COM5 --baud 115200 --vector-set basic --timeout 10
```

Result:

| Vector | Mode | Result |
| --- | --- | --- |
| `identity_gs4` | GS-4 | PASS |
| `phase6_real_nondiagonal_gs4` | GS-4 | PASS |
| `phase6_complex_noise_gs8` | GS-8 | PASS |
| `phase6_complex_noise_gs16` | GS-16 | PASS |

Mode coverage:

```text
GS-4: 2
GS-8: 1
GS-16: 1
Total: 4/4 PASS
```

Interpretation:

This proves the hardware UART validation path works for multiple deterministic vectors and covers all adaptive modes: GS-4, GS-8, and GS-16.

## 6. 20-Vector Regression Result

Command used:

```powershell
python python\uart_batch_regression.py --port COM5 --baud 115200 --vector-set phase6_20 --timeout 10 *>&1 | Tee-Object -FilePath results\phase9_zedboard_uart\clk_20p000ns\uart_batch_phase6_20_hw_log.txt
```

Log path:

```text
results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_20_hw_log.txt
```

Result:

| Metric | Value |
| --- | --- |
| Total vectors | 20 |
| Result | 20/20 PASS |
| GS-4 | 3 |
| GS-8 | 2 |
| GS-16 | 15 |
| Identity source vectors | 1 |
| Phase 6 JSON source vectors | 19 |

Interpretation:

This was the first larger physical ZedBoard hardware regression. It validated 20 deterministic vectors. For all 20 vectors, the FPGA outputs matched the Python fixed-point golden model exactly for `mode`, `num_iters`, `bits`, `xout_re`, and `xout_im`.

The mode distribution was not balanced because the Phase 6 JSON vectors available at that point naturally produced more GS-16 cases.

## 7. 50-Vector Regression Result

Command used:

```powershell
python python\uart_batch_regression.py --port COM5 --baud 115200 --vector-set phase6_50 --timeout 10 *>&1 | Tee-Object -FilePath results\phase9_zedboard_uart\clk_20p000ns\uart_batch_phase6_50_hw_log.txt
```

Log path:

```text
results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_50_hw_log.txt
```

Result:

| Metric | Value |
| --- | --- |
| Vector set | `phase6_50` |
| Selected vectors | 50 |
| Result | 50/50 PASS |
| GS-4 | 17 |
| GS-8 | 17 |
| GS-16 | 16 |
| Identity source vectors | 1 |
| Phase 6 JSON source vectors | 49 |

Interpretation:

A 50-vector PC-driven UART hardware regression passed on physical ZedBoard. The regression covered all adaptive modes with near-balanced coverage: 17 GS-4, 17 GS-8, and 16 GS-16 vectors. Across all 50 vectors, the FPGA outputs matched the Python fixed-point golden model exactly for adaptive mode selection, iteration count, detected QPSK bits, and fixed-point `xout` values.

This is the strongest hardware regression result so far.

## 8. Summary Table

| Test | Command/vector set | Vectors | GS-4 | GS-8 | GS-16 | Exact mode match | Exact xout match | Exact bits match | Result |
| --- | --- | ---: | ---: | ---: | ---: | --- | --- | --- | --- |
| Identity | `uart_send_vector identity` | 1 | 1 | 0 | 0 | yes | yes | yes | PASS |
| Basic | `basic` | 4 | 2 | 1 | 1 | yes | yes | yes | PASS |
| Phase6 20 | `phase6_20` | 20 | 3 | 2 | 15 | yes | yes | yes | PASS |
| Phase6 50 | `phase6_50` | 50 | 17 | 17 | 16 | yes | yes | yes | PASS |

## 9. Evidence Files

Hardware regression logs:

- `results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_20_hw_log.txt`
- `results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_50_hw_log.txt`

Programmed design artifacts:

- `results/phase9_zedboard_uart/clk_20p000ns/zedboard_mimo_uart_top.bit`
- `results/phase9_zedboard_uart/clk_20p000ns/routed_zedboard_uart_demo.dcp`

Vivado implementation reports:

- `results/phase9_zedboard_uart/clk_20p000ns/utilization_post_route.rpt`
- `results/phase9_zedboard_uart/clk_20p000ns/timing_post_route.rpt`
- `results/phase9_zedboard_uart/clk_20p000ns/power_post_route.rpt`

## 10. Conclusion

The sequential adaptive fixed-point GS MIMO detector was validated on a physical ZedBoard using a PC-driven UART regression flow. Across 50 deterministic fixed-point MIMO vectors, the FPGA returned outputs that matched the Python fixed-point golden model exactly for adaptive mode selection, iteration count, detected QPSK bits, and fixed-point detector outputs. The 50-vector set covered all adaptive modes with near-balanced mode coverage: 17 GS-4, 17 GS-8, and 16 GS-16 cases.

## Related Results Tables

Paper-ready fixed-point, verification, and FPGA implementation comparison tables are collected in `docs/final_result_tables.md`.
