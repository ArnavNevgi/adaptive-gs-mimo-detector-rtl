# FPGA Implementation and I/O Validation

## 1. Purpose of This Document

This document records how the adaptive fixed-point Gauss-Seidel MIMO detector RTL was implemented on FPGA and how real hardware inputs and outputs were validated.

The focus is the hardware I/O validation flow: how fixed-point test data was generated, how that data was sent from a PC to the FPGA, how the FPGA ran the detector, how the output packet was returned, and how the returned values were checked against the Python fixed-point golden model.

This document is intentionally separate from the RTL directories. It is a root-level summary that links back to the existing implementation files, reports, scripts, and detailed notes.

## Related Existing Documentation

- [Project README](README.md)
- [ZedBoard PL UART MIMO demo](docs/zedboard_uart_demo.md)
- [UART hardware regression results](docs/uart_hardware_regression_results.md)
- [ZedBoard bring-up demo](docs/zedboard_bringup.md)
- [Phase 8 sequential architecture](docs/phase8_sequential_architecture.md)
- [Step 8 sequential architecture notes](docs/step8_sequential_architecture.md)
- [Final result tables](docs/final_result_tables.md)
- [Latency and throughput results](docs/latency_throughput_results.md)
- [Sequential RTL simulation notes](sim_seq/README_sim_seq.md)
- [Sequential Vivado synthesis notes](syn_seq/README_synthesis_seq.md)
- [Sequential Vivado implementation notes](syn_seq/README_implementation_seq.md)

## 2. FPGA Target and Setup

The final UART hardware-validation target in this repository is the ZedBoard Zynq-7000 board using the Xilinx part `xc7z020clg484-1`. This is confirmed by the [README](README.md), the ZedBoard UART implementation Tcl flow [syn_seq/vivado_impl_zedboard_uart_demo.tcl](syn_seq/vivado_impl_zedboard_uart_demo.tcl), and the routed reports under [results/phase9_zedboard_uart/clk_20p000ns/](results/phase9_zedboard_uart/clk_20p000ns/).

The main hardware-validation top is [rtl_seq/zedboard_mimo_uart_top.sv](rtl_seq/zedboard_mimo_uart_top.sv). It wraps:

- the UART receiver [rtl_seq/uart_rx.sv](rtl_seq/uart_rx.sv)
- the UART transmitter [rtl_seq/uart_tx.sv](rtl_seq/uart_tx.sv)
- the UART packet/protocol logic [rtl_seq/uart_mimo_protocol.sv](rtl_seq/uart_mimo_protocol.sv)
- the sequential adaptive detector [rtl_seq/mimo_detector_top_seq.sv](rtl_seq/mimo_detector_top_seq.sv)

The ZedBoard UART build uses [constraints/zedboard_uart_demo.xdc](constraints/zedboard_uart_demo.xdc). That constraint file maps the board clock, reset button, LED outputs, and the PL UART pins. It also documents an important board-level point: the onboard ZedBoard USB-UART is connected to the Zynq PS MIO pins, so this pure-PL UART demo uses an external 3.3 V USB-UART adapter connected to JA Pmod pins.

Confirmed UART wiring:

```text
CP2102 TXD -> ZedBoard JA1 / Y11  -> FPGA uart_rx_i
CP2102 RXD -> ZedBoard JA2 / AA11 -> FPGA uart_tx_o
CP2102 GND -> ZedBoard JA Pmod GND
CP2102 3V3 -> not connected
CP2102 +5V -> not connected
```

JTAG was used from Vivado Hardware Manager to program the FPGA bitstream. UART was then used after programming to send test vectors and receive detector outputs. JTAG and UART have separate roles in this project.

The repository also contains earlier Artix-7 sequential synthesis and implementation flows for `xc7a35tcpg236-1`, documented in [syn_seq/README_synthesis_seq.md](syn_seq/README_synthesis_seq.md) and [syn_seq/README_implementation_seq.md](syn_seq/README_implementation_seq.md). The physical PC-to-FPGA UART validation described here is the ZedBoard flow.

## 3. High-Level Hardware Flow

At a high level, the project validates the hardware by sending deterministic fixed-point MIMO vectors from a PC to the programmed FPGA and comparing the returned detector result against the Python fixed-point golden model.

```text
Python Golden Model
       |
       v
Fixed-Point Test Vectors
       |
       v
PC Host Script
       |
       | UART input packet
       v
FPGA UART RX
       |
       v
UART Protocol Parser
       |
       v
MIMO Detector RTL
       |
       v
FPGA UART TX
       |
       | UART output packet
       v
PC Captures Output
       |
       v
Golden Comparison / PASS-FAIL
```

UART is only the hardware validation and host-control interface. It is not the MIMO RF datapath and it is not part of the detector algorithm itself. The detector receives already-quantized fixed-point `H`, `y`, `noise_var`, and `snr_level` values through the UART packet.

## 4. How Input Data Was Generated

The inputs came from the Python modeling and fixed-point export flow. The repository contains floating-point and fixed-point development scripts, including:

- [python/phase1_float_4x4.py](python/phase1_float_4x4.py)
- [python/phase2_adaptive_float_4x4.py](python/phase2_adaptive_float_4x4.py)
- [python/phase3_fixed_point_4x4.py](python/phase3_fixed_point_4x4.py)
- [python/phase4_scaling_fixed_point.py](python/phase4_scaling_fixed_point.py)
- [python/export_phase6_rtl_vectors.py](python/export_phase6_rtl_vectors.py)
- [python/final_algorithm_plots.py](python/final_algorithm_plots.py)

The key vector export script for RTL and UART validation is [python/export_phase6_rtl_vectors.py](python/export_phase6_rtl_vectors.py). It uses fixed-point helper functions that mirror the RTL datapath: quantization, Gram matrix generation, matched filtering, regularization, adaptive mode selection, GS solving, QPSK slicing, and expected output generation.

The generated vector files checked into the repository include:

- [vectors/phase6_rtl_vectors/phase6_vectors_summary.json](vectors/phase6_rtl_vectors/phase6_vectors_summary.json)
- [vectors/phase6_rtl_vectors/phase6_uart_50_vectors_summary.json](vectors/phase6_rtl_vectors/phase6_uart_50_vectors_summary.json)
- [tb/phase6_vectors_pkg.sv](tb/phase6_vectors_pkg.sv)

Each fixed-point vector includes:

- `H_re` and `H_im`, the 4x4 complex channel matrix in Q4.12
- `y_re` and `y_im`, the received vector in Q4.12
- `noise_var_int`, the fixed-point noise variance used for regularization
- `snr_level`, the compact SNR category used by the adaptive policy
- expected `mode`
- expected `num_iters`
- expected QPSK `bits`
- expected `xout_re` and `xout_im`

The UART 50-vector JSON file was generated by the documented command:

```powershell
python python/export_phase6_rtl_vectors.py --profile uart --num-vectors 50 --json-output vectors/phase6_rtl_vectors/phase6_uart_50_vectors_summary.json --skip-sv
```

The checked-in SystemVerilog package [tb/phase6_vectors_pkg.sv](tb/phase6_vectors_pkg.sv) currently contains `NUM_PHASE6_VECTORS = 20`. The 50-vector UART regression uses the JSON file [vectors/phase6_rtl_vectors/phase6_uart_50_vectors_summary.json](vectors/phase6_rtl_vectors/phase6_uart_50_vectors_summary.json).

## 5. How Input Data Was Fed to the FPGA

Input data was fed from the PC to the FPGA over UART. The PC-side scripts are:

- [python/uart_send_vector.py](python/uart_send_vector.py), used for the single identity-vector check
- [python/uart_batch_regression.py](python/uart_batch_regression.py), used for the multi-vector hardware regressions

The host script serializes each vector into a binary `RUN_VECTOR` packet. The request frame is:

```text
0xA5 0x5A
command
payload_length_low
payload_length_high
payload bytes
checksum
```

The command byte is `0x01`, meaning `RUN_VECTOR`. The `RUN_VECTOR` payload is 85 bytes:

```text
uint8 snr_level
int32 noise_var, little-endian, lower Q8.12 bits used by the FPGA
int16 H_re[4][4], little-endian, row-major
int16 H_im[4][4], little-endian, row-major
int16 y_re[4], little-endian
int16 y_im[4], little-endian
```

Including the header, command, length, payload, and checksum, the request frame is 91 bytes. The packet format is documented in [docs/zedboard_uart_demo.md](docs/zedboard_uart_demo.md) and implemented in [python/uart_send_vector.py](python/uart_send_vector.py), [python/uart_batch_regression.py](python/uart_batch_regression.py), and [rtl_seq/uart_mimo_protocol.sv](rtl_seq/uart_mimo_protocol.sv).

On the FPGA side:

1. [rtl_seq/uart_rx.sv](rtl_seq/uart_rx.sv) receives 8N1 UART bytes.
2. [rtl_seq/uart_mimo_protocol.sv](rtl_seq/uart_mimo_protocol.sv) searches for the request header, checks the command, checks the payload length, accumulates the checksum, and stores payload bytes.
3. After a valid complete packet is received, the protocol logic reconstructs `snr_level`, `noise_var`, `H_re`, `H_im`, `y_re`, and `y_im`.
4. The protocol asserts `detector_start` for the real sequential detector.
5. [rtl_seq/mimo_detector_top_seq.sv](rtl_seq/mimo_detector_top_seq.sv) runs until `done` is asserted.

The top-level ZedBoard wrapper [rtl_seq/zedboard_mimo_uart_top.sv](rtl_seq/zedboard_mimo_uart_top.sv) uses `UART_CLKS_PER_BIT = 434` with the generated 50 MHz clock, matching the 115200 baud host setting used in the hardware logs.

## 6. FPGA Computation Flow

Once a valid UART input packet has been accepted, the FPGA runs the sequential/resource-shared fixed-point detector.

The main detector top is [rtl_seq/mimo_detector_top_seq.sv](rtl_seq/mimo_detector_top_seq.sv). It sequences these blocks:

- [rtl_seq/gram_matrix_seq.sv](rtl_seq/gram_matrix_seq.sv): computes `G = H^H H`
- [rtl_seq/matched_filter_seq.sv](rtl_seq/matched_filter_seq.sv): computes `b = H^H y`
- [rtl_seq/regularization_metric_seq.sv](rtl_seq/regularization_metric_seq.sv): computes `W = G + noise_var I` and the diagonal/off-diagonal metric
- [rtl/mode_select_unit.sv](rtl/mode_select_unit.sv): selects GS-4, GS-8, or GS-16
- [rtl_seq/gs_solver_seq.sv](rtl_seq/gs_solver_seq.sv): runs the sequential fixed-point GS solver
- [rtl_seq/signed_divider_seq.sv](rtl_seq/signed_divider_seq.sv): provides the multi-cycle signed division used by the GS solver
- [rtl/x_to_xout_converter.sv](rtl/x_to_xout_converter.sv): converts internal Q6.16 solver outputs to Q4.12 `xout`
- [rtl/qpsk_slicer_array.sv](rtl/qpsk_slicer_array.sv): slices the signs of `xout` into detected QPSK bits

The fixed-point formats are defined in [rtl/fixed_point_pkg.sv](rtl/fixed_point_pkg.sv). The main formats used by this flow are:

| Signal | Format | Width | Purpose |
| ------ | ------ | ----- | ------- |
| `H` and `y` | Q4.12 | 16-bit signed | UART-fed channel and received-vector inputs |
| `G`, `b`, and `W` | Q8.12 | 20-bit signed | Gram matrix, matched filter, and regularized system |
| accumulator | Q12.16 | 28-bit signed | complex multiply-accumulate margin |
| internal `x` | Q6.16 | 22-bit signed | GS solver internal estimate |
| `xout` | Q4.12 | 16-bit signed | detector output and slicer input |

The implemented adaptive policy is in [rtl/mode_select_unit.sv](rtl/mode_select_unit.sv):

```text
if snr_level >= 2 and 100*diag_sum >= 105*offdiag_sum:
    mode = GS-4
elif snr_level >= 1 and 100*diag_sum >= 80*offdiag_sum:
    mode = GS-8
else:
    mode = GS-16
```

The sequential implementation reuses arithmetic resources over multiple cycles. That is the hardware-oriented architecture used for synthesis, implementation, and the ZedBoard UART validation. The earlier baseline/unrolled RTL remains under [rtl/](rtl/), while the validated sequential path is under [rtl_seq/](rtl_seq/).

## 7. How Output Was Captured

After the detector asserts `done`, [rtl_seq/uart_mimo_protocol.sv](rtl_seq/uart_mimo_protocol.sv) packs the detector result into a UART response packet. The response frame is:

```text
0x5A 0xA5
status
payload_length_low
payload_length_high
payload bytes
checksum
```

The OK status value is `0x00`. The OK payload is 22 bytes:

```text
uint8 mode
uint8 num_iters
uint8 bits[0]
uint8 bits[1]
uint8 bits[2]
uint8 bits[3]
int16 xout_re[4], little-endian
int16 xout_im[4], little-endian
```

The FPGA sends the response bytes through [rtl_seq/uart_tx.sv](rtl_seq/uart_tx.sv). On the PC side, [python/uart_send_vector.py](python/uart_send_vector.py) and [python/uart_batch_regression.py](python/uart_batch_regression.py) read the response header, status, length, payload, and checksum. The host then decodes the payload into human-readable fields.

The hardware checker compares the FPGA response against the expected golden values:

- `mode`
- `num_iters`
- detected QPSK `bits`
- `xout_re`
- `xout_im`

The comparison is exact in the current UART regression script. No tolerance is applied.

## 8. Validation Results

The repository contains hardware logs, routed reports, and summary docs for the ZedBoard UART validation.

### UART Hardware PASS Results

| Validation run | Evidence | Result |
| --- | --- | --- |
| Identity vector | [docs/zedboard_uart_demo.md](docs/zedboard_uart_demo.md), [docs/uart_hardware_regression_results.md](docs/uart_hardware_regression_results.md) | PASS, mode 0 / GS-4, `num_iters = 4`, bits `00 01 11 10` |
| 4-vector basic regression | [results/phase9_zedboard_uart/clk_20p000ns/uart_batch_basic_hw_log.txt](results/phase9_zedboard_uart/clk_20p000ns/uart_batch_basic_hw_log.txt), [docs/uart_hardware_regression_results.md](docs/uart_hardware_regression_results.md) | 4/4 PASS, GS-4: 2, GS-8: 1, GS-16: 1 |
| 20-vector regression | [results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_20_hw_log.txt](results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_20_hw_log.txt), [docs/uart_hardware_regression_results.md](docs/uart_hardware_regression_results.md) | 20/20 PASS, GS-4: 3, GS-8: 2, GS-16: 15 |
| 50-vector regression | [results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_50_hw_log.txt](results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_50_hw_log.txt), [results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_50_hw_repeat_log.txt](results/phase9_zedboard_uart/clk_20p000ns/uart_batch_phase6_50_hw_repeat_log.txt), [docs/uart_hardware_regression_results.md](docs/uart_hardware_regression_results.md) | 50/50 PASS, GS-4: 17, GS-8: 17, GS-16: 16 |

The 50-vector hardware log shows exact matches for all returned fields checked by the host script: `mode`, `num_iters`, `bits`, `xout_re`, and `xout_im`.

### Vivado Implementation Evidence

The ZedBoard UART implementation flow is [syn_seq/vivado_impl_zedboard_uart_demo.tcl](syn_seq/vivado_impl_zedboard_uart_demo.tcl). It reads the sequential RTL filelist [syn_seq/filelist_rtl_seq.tcl](syn_seq/filelist_rtl_seq.tcl), adds the UART demo RTL files, reads [constraints/zedboard_uart_demo.xdc](constraints/zedboard_uart_demo.xdc), runs synthesis, optimization, placement, physical optimization, routing, report generation, checkpoint writing, and bitstream generation.

Confirmed implementation artifacts:

- [results/phase9_zedboard_uart/clk_20p000ns/zedboard_mimo_uart_top.bit](results/phase9_zedboard_uart/clk_20p000ns/zedboard_mimo_uart_top.bit)
- [results/phase9_zedboard_uart/clk_20p000ns/routed_zedboard_uart_demo.dcp](results/phase9_zedboard_uart/clk_20p000ns/routed_zedboard_uart_demo.dcp)
- [results/phase9_zedboard_uart/clk_20p000ns/timing_post_route.rpt](results/phase9_zedboard_uart/clk_20p000ns/timing_post_route.rpt)
- [results/phase9_zedboard_uart/clk_20p000ns/utilization_post_route.rpt](results/phase9_zedboard_uart/clk_20p000ns/utilization_post_route.rpt)
- [results/phase9_zedboard_uart/clk_20p000ns/power_post_route.rpt](results/phase9_zedboard_uart/clk_20p000ns/power_post_route.rpt)
- [results/phase9_zedboard_uart/clk_20p000ns/route_status_post_route.rpt](results/phase9_zedboard_uart/clk_20p000ns/route_status_post_route.rpt)

The routed timing report [results/phase9_zedboard_uart/clk_20p000ns/timing_post_route.rpt](results/phase9_zedboard_uart/clk_20p000ns/timing_post_route.rpt) reports:

```text
WNS = +3.153 ns
TNS = 0.000 ns
All user specified timing constraints are met.
```

The post-route utilization report [results/phase9_zedboard_uart/clk_20p000ns/utilization_post_route.rpt](results/phase9_zedboard_uart/clk_20p000ns/utilization_post_route.rpt) reports:

```text
Slice LUTs:      3322
Slice Registers: 4102
DSPs:              12
Block RAM Tile:     0
```

The post-route route status report [results/phase9_zedboard_uart/clk_20p000ns/route_status_post_route.rpt](results/phase9_zedboard_uart/clk_20p000ns/route_status_post_route.rpt) reports zero nets with routing errors. The post-route power report [results/phase9_zedboard_uart/clk_20p000ns/power_post_route.rpt](results/phase9_zedboard_uart/clk_20p000ns/power_post_route.rpt) reports total on-chip power of 0.236 W.

### RTL Regression Notes

The summary documents [docs/final_result_tables.md](docs/final_result_tables.md) and [docs/phase8_sequential_architecture.md](docs/phase8_sequential_architecture.md) record 100-vector PASS results for the unrolled RTL baseline and the sequential/resource-shared RTL. The current checked-in [tb/phase6_vectors_pkg.sv](tb/phase6_vectors_pkg.sv) contains 20 vectors, and the scan did not find a raw 100-vector simulator transcript.

TODO: If a raw 100-vector simulator transcript is needed for archival evidence, add it under `results/` or `docs/` and link it here.

## 9. JTAG Programming Role

JTAG was used to configure the FPGA fabric with the generated bitstream. The programming flow is documented in [docs/zedboard_uart_demo.md](docs/zedboard_uart_demo.md) and [docs/uart_hardware_regression_results.md](docs/uart_hardware_regression_results.md).

For the UART hardware validation, Vivado Hardware Manager detected the ZedBoard hardware chain and the PL device `xc7z020_1`; the FPGA was programmed with:

```text
results/phase9_zedboard_uart/clk_20p000ns/zedboard_mimo_uart_top.bit
```

JTAG was not used to feed MIMO test vectors. It only loaded the bitstream into the FPGA. After the bitstream was programmed, the PC sent MIMO vectors using UART.

This distinction matters:

- JTAG programs/configures the FPGA.
- UART sends test input data and receives output data after programming.

## 10. Step-by-Step Reproduction Flow

Run commands from the repository root unless a step says otherwise.

1. Install Python UART dependency if it is not already installed.

   ```powershell
   python -m pip install pyserial
   ```

2. Generate or refresh the 50-vector UART fixed-point JSON set.

   ```powershell
   python python/export_phase6_rtl_vectors.py --profile uart --num-vectors 50 --json-output vectors/phase6_rtl_vectors/phase6_uart_50_vectors_summary.json --skip-sv
   ```

3. Run host-side packet construction checks without hardware.

   ```powershell
   python python/uart_send_vector.py --dry-run
   python python/uart_batch_regression.py --dry-run --vector-set basic
   python python/uart_batch_regression.py --dry-run --vector-set phase6_50
   ```

4. Run RTL simulations when the required simulators are available.

   Questa full sequential regression:

   ```powershell
   vsim -do sim_seq/run_all_seq.do
   ```

   Vivado XSIM UART protocol and integration checks:

   ```powershell
   C:\AMDDesignTools\2025.2.1\Vivado\bin\xtclsh.bat sim_seq\xsim_uart_mimo_protocol.tcl
   C:\AMDDesignTools\2025.2.1\Vivado\bin\xtclsh.bat sim_seq\xsim_uart_mimo_detector_integration.tcl
   ```

5. Build the ZedBoard UART bitstream using the Vivado Tcl implementation flow.

   ```powershell
   C:\AMDDesignTools\2025.2.1\Vivado\bin\vivado.bat -mode batch -source syn_seq\vivado_impl_zedboard_uart_demo.tcl -tclargs -clock_period 20.000 -part xc7z020clg484-1
   ```

6. Review the generated implementation reports.

   Important report paths:

   - [results/phase9_zedboard_uart/clk_20p000ns/timing_post_route.rpt](results/phase9_zedboard_uart/clk_20p000ns/timing_post_route.rpt)
   - [results/phase9_zedboard_uart/clk_20p000ns/utilization_post_route.rpt](results/phase9_zedboard_uart/clk_20p000ns/utilization_post_route.rpt)
   - [results/phase9_zedboard_uart/clk_20p000ns/power_post_route.rpt](results/phase9_zedboard_uart/clk_20p000ns/power_post_route.rpt)
   - [results/phase9_zedboard_uart/clk_20p000ns/route_status_post_route.rpt](results/phase9_zedboard_uart/clk_20p000ns/route_status_post_route.rpt)

7. Program the ZedBoard over JTAG.

   Use Vivado Hardware Manager:

   1. Power on the ZedBoard.
   2. Connect USB-JTAG/PROG to the PC.
   3. Open Hardware Manager.
   4. Open target and auto-connect.
   5. Select the `xc7z020` PL device.
   6. Program [results/phase9_zedboard_uart/clk_20p000ns/zedboard_mimo_uart_top.bit](results/phase9_zedboard_uart/clk_20p000ns/zedboard_mimo_uart_top.bit).

   A Tcl programming outline is included in [docs/zedboard_uart_demo.md](docs/zedboard_uart_demo.md). No standalone programming Tcl script was found during this scan.

   TODO: Confirm whether a reusable JTAG programming Tcl script should be added in a future documentation/script cleanup.

8. Connect the external USB-UART adapter.

   Use the wiring from [constraints/zedboard_uart_demo.xdc](constraints/zedboard_uart_demo.xdc) and [docs/zedboard_uart_demo.md](docs/zedboard_uart_demo.md):

   ```text
   CP2102 TXD -> ZedBoard JA1 / Y11
   CP2102 RXD -> ZedBoard JA2 / AA11
   CP2102 GND -> ZedBoard JA Pmod GND
   ```

9. Run a single-vector hardware check.

   Replace `COM5` with the actual adapter COM port.

   ```powershell
   python python/uart_send_vector.py --port COM5 --baud 115200 --vector identity
   ```

10. Run the batch hardware regression.

    Basic 4-vector regression:

    ```powershell
    python python/uart_batch_regression.py --port COM5 --baud 115200 --vector-set basic --timeout 10
    ```

    Full 50-vector hardware regression:

    ```powershell
    python python/uart_batch_regression.py --port COM5 --baud 115200 --vector-set phase6_50 --timeout 10
    ```

11. Capture a hardware log when recording final evidence.

    ```powershell
    python python\uart_batch_regression.py --port COM5 --baud 115200 --vector-set phase6_50 --timeout 10 *>&1 | Tee-Object -FilePath results\phase9_zedboard_uart\clk_20p000ns\uart_batch_phase6_50_hw_log.txt
    ```

12. Check the final PASS/FAIL summary.

    The expected confirmed result in the checked-in 50-vector log is:

    ```text
    Total: 50/50 PASS
    Mode coverage:
    GS-4: 17
    GS-8: 17
    GS-16: 16
    ```

## 11. Summary

The FPGA validation proved that the fixed-point RTL implementation could be programmed onto real ZedBoard hardware, accept externally supplied fixed-point MIMO test vectors through UART, run the adaptive sequential GS MIMO detector, and return outputs that matched the Python fixed-point golden results exactly for the validated hardware vectors.

JTAG configured the FPGA with the generated bitstream. UART carried the test-vector input packets and detector-output response packets. Python generated the golden fixed-point vectors and performed the PASS/FAIL comparison.

The strongest checked-in hardware result is the 50-vector ZedBoard UART regression: 50/50 PASS with exact matches for mode selection, iteration count, detected bits, and fixed-point `xout` values.
