# Final Result Tables

## Purpose

This document collects the main paper/report tables for the project, "FPGA Implementation of an Adaptive Fixed-Point Gauss-Seidel Detector for 4x4 QPSK MIMO Systems." The tables summarize the fixed-point design, RTL and hardware verification, and FPGA implementation comparison for the adaptive fixed-point GS MIMO detector.

## Table 1. Fixed-Point Format Summary

| Signal | Format | Width | Reason |
| ------ | -----: | ----: | ------ |
| H/y | Q4.12 | 16-bit signed | Input channel and received-vector precision |
| G/b/W | Q8.12 | 20-bit signed | Gram matrix, matched-filter, and regularized-system dynamic range |
| ACC | Q12.16 | 28-bit signed | Accumulation margin for complex multiply-accumulate operations |
| x | Q6.16 | 22-bit signed | Internal Gauss-Seidel solution estimate |
| xout | Q4.12 | 16-bit signed | Detector output format used by slicer and UART response |

### Inference

The selected fixed-point formats separate input precision, intermediate dynamic range, accumulator growth, internal solver precision, and output precision. Q4.12 represents +1.0 as 4096 and -1.0 as -4096, matching the QPSK detector output scale used in the UART hardware checks. Wider formats for G/b/W, ACC, and x reduce overflow risk during Gram matrix generation, matched filtering, regularization, and iterative GS computation. These formats were validated earlier against the Python fixed-point golden model and used consistently in the RTL and hardware validation flow.

## Table 2. RTL and Hardware Verification Summary

| Design version | Vectors | Modes covered | xout match | bits match | Result |
| --- | ---: | --- | --- | --- | --- |
| Unrolled RTL baseline | 100 | GS-4 / GS-8 / GS-16 | Exact | Exact | PASS |
| Sequential resource-shared RTL | 100 | GS-4 / GS-8 / GS-16 | Exact | Exact | PASS |
| ZedBoard UART hardware | 50 | GS-4 / GS-8 / GS-16 | Exact | Exact | PASS |

The ZedBoard UART hardware row is based on the physical `phase6_50` hardware regression. That set had mode coverage GS-4: 17, GS-8: 17, and GS-16: 16. The hardware checker compared `mode`, `num_iters`, `bits`, `xout_re`, and `xout_im` exactly against the Python fixed-point golden model.

### Inference

The unrolled RTL and sequential RTL were both verified against Python-generated fixed-point vectors. The sequential architecture preserved bit-exact behavior relative to the golden model while enabling practical FPGA implementation. The ZedBoard UART hardware regression proves that the actual programmed FPGA, not only simulation, produces exact golden-model outputs for 50 deterministic vectors. Since the 50-vector hardware set covers GS-4, GS-8, and GS-16, it validates the adaptive mode-selection path as well as the datapath. This is vector-driven fixed-point hardware validation over UART, not a hardware BER, RF, or over-the-air MIMO measurement.

## Table 3. FPGA Implementation Comparison

| Architecture | LUTs | FFs | DSPs | BRAM | WNS | Result |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Unrolled baseline | ~116,619 | Not reported | 90 | Not reported | -189.965 ns | Failed placement / infeasible |
| Sequential resource-shared RTL | ~2,962 | ~2,289 | 12 | 0 | +2.391 ns | Feasible |
| ZedBoard UART top | 3,322 | 4,102 | 12 | 0 | +3.153 ns | Bitstream generated and hardware-validated |

Sequential synthesis utilization is reported in `results/phase8_synthesis_seq/utilization_seq.rpt`, and the routed sequential WNS is reported in `results/phase8_impl_seq/clk_20p000ns/timing_impl.rpt`. The ZedBoard UART top utilization and WNS are reported in `results/phase9_zedboard_uart/clk_20p000ns/utilization_post_route.rpt` and `results/phase9_zedboard_uart/clk_20p000ns/timing_post_route.rpt`. Exact unrolled FF and BRAM values were not available in the current implementation report set, so those fields are left as "Not reported."

### Inference

The unrolled baseline was not FPGA-feasible because resource usage exceeded the target device and timing was severely negative. The sequential resource-shared architecture reduced the design to a practical implementation by reusing compute resources. The ZedBoard UART top adds UART/protocol logic but still remains small: 3,322 LUTs, 4,102 FFs, 12 DSPs, 0 BRAM, and +3.153 ns WNS. This table is one of the strongest results because it shows the architectural transformation from an infeasible unrolled design to a timing-clean, hardware-validated FPGA implementation.

## Notes for Paper Use

Table 1 supports the fixed-point design section. Table 2 supports the verification and hardware validation section. Table 3 supports the architecture and FPGA implementation results section.

The strongest combined claim is that the resource-shared sequential detector preserved exact fixed-point behavior while reducing the design from infeasible unrolled RTL to a timing-clean ZedBoard implementation validated over 50 UART-fed hardware vectors.
