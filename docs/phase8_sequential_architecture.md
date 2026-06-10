# Phase 8 Sequential Architecture

## Purpose

Phase 8 converts the verified fixed-point MIMO detector from a large unrolled RTL baseline into an area-optimized sequential architecture for the Artix-7 `xc7a35tcpg236-1`.

The algorithm is unchanged:

- 4x4 MIMO QPSK detection
- Fixed-point Gram matrix `G = H^H H`
- Matched filter `b = H^H y`
- Noise regularization
- Condition-metric based adaptive GS iteration count
- Gauss-Seidel solve using GS-4, GS-8, or GS-16
- Q4.12 output conversion and QPSK slicing

The architectural change is resource sharing. Phase 8 trades latency for much lower LUT, DSP, and carry-chain pressure.

## RTL Directory Roles

The project intentionally keeps two RTL architecture trees.

### `rtl/`

`rtl/` is the verified unrolled baseline RTL.

Use it as:

- Functional reference RTL
- Phase 6 vector verification reference
- Comparison point for area and timing
- Evidence of the first direct hardware mapping attempt

Do not treat `rtl/` as the area-optimized target for `xc7a35t`. It is intentionally more parallel and combinational.

### `rtl_seq/`

`rtl_seq/` is the sequential, resource-shared architecture.

Use it as:

- Optimized Phase 8 RTL
- FPGA synthesis target
- Source for implementation/place-and-route experiments
- Current candidate architecture for the `xc7a35tcpg236-1`

The sequential RTL has passed the same 100 Phase 6 vectors bit-exactly.

## Architecture Progression

| Step | Architecture | Purpose | Result |
| --- | --- | --- | --- |
| Python floating-point model | Floating-point detector | Establish algorithm and adaptive policy | Functional model completed |
| Fixed-point model | Quantized detector | Match RTL arithmetic intent | Fixed-point behavior established |
| `rtl/` unrolled RTL | Parallel baseline | Prove algorithm-to-RTL correctness | Passed 100 Phase 6 vectors |
| Unrolled Vivado synthesis | Direct FPGA mapping | Measure first hardware cost | Did not fit target FPGA |
| `rtl_seq/` sequential RTL | Resource-shared design | Reduce FPGA area | Passed 100 vectors and fits synthesis area |
| Step 8.9 divider fix | Sequential divider in GS solver | Remove combinational divider critical path | Large timing improvement |

## Why The Unrolled RTL Failed

The unrolled baseline computes many arithmetic operations in parallel:

- Gram matrix entries are built through broad combinational logic.
- Matched-filter outputs are built through broad combinational logic.
- The GS solver contains behavioral division.
- Several wide fixed-point arithmetic paths exist in the same cycle.

This made the design useful as a golden RTL reference, but too large for the first Artix-7 target.

| Architecture | LUTs | FFs | DSPs | BRAM | Timing |
| --- | ---: | ---: | ---: | ---: | ---: |
| Unrolled baseline RTL | 116,619 / 20,800 = 560.67% | 374 / 41,600 = 0.90% | 90 / 90 = 100% | Not limiting | WNS about -189.965 ns |

Placement failed due to over-utilization, so this was not a valid implementation candidate for `xc7a35t`.

## Why Sequential Resource Sharing Was Introduced

The sequential architecture reuses arithmetic datapaths over multiple cycles:

- `gram_matrix_seq` builds `G` entry-by-entry.
- `matched_filter_seq` builds `b` stream-by-stream.
- `regularization_metric_seq` combines regularization and condition metric accumulation.
- `gs_solver_seq` reuses one GS update datapath across index and iteration loops.
- `mimo_detector_top_seq` sequences the engines with an FSM.

This lowers area at the cost of latency. That is the intended FPGA architecture tradeoff for Phase 8.

## Step 8.9 Timing Problem

After resource sharing, area fit but timing still failed badly.

The root cause was behavioral division in `rtl_seq/gs_solver_seq.sv`. The old helper used a division expression equivalent to:

```systemverilog
quot = num_shift / den;
```

Vivado synthesized this as a large combinational divider in the GS update cycle. The worst path came from matched-filter output registers into `gs_solver_seq` output registers through this divider logic.

Before the fix:

| Metric | Sequential RTL before divider fix |
| --- | ---: |
| LUTs | 15,561 / 20,800 = 74.81% |
| FFs | 2,127 / 41,600 = 5.11% |
| DSPs | 12 / 90 = 13.33% |
| BRAM | 0 / 50 = 0.00% |
| CARRY4 | 3,632 |
| WNS at 10 ns | -173.984 ns |
| Data path delay | 183.929 ns |

## `signed_divider_seq` Fix

Step 8.9 replaced the combinational division in `gs_solver_seq` with `rtl_seq/signed_divider_seq.sv`.

The divider:

- Performs signed division over multiple cycles.
- Preserves truncate-toward-zero quotient behavior.
- Returns zero on divide-by-zero, matching the old helper.
- Keeps the external solver behavior bit-exact.
- Adds latency, which is acceptable for the sequential architecture.

After the fix:

| Metric | Sequential RTL after `signed_divider_seq` |
| --- | ---: |
| LUTs | 3,024 / 20,800 = 14.54% |
| FFs | 2,289 / 41,600 = 5.50% |
| DSPs | 12 / 90 = 13.33% |
| BRAM | 0 / 50 = 0.00% |
| CARRY4 | 255 |
| WNS at 10 ns | -4.130 ns |
| Data path delay | about 14.075 ns |

This is a major synthesis improvement. It is still synthesis timing, not post-route timing.

## Clock Sweep After Divider Fix

| Clock period | Frequency | Synthesis result | WNS |
| ---: | ---: | --- | ---: |
| 20.0 ns | 50.0 MHz | PASS | +5.918 ns |
| 15.0 ns | 66.7 MHz | PASS | +0.918 ns |
| 12.5 ns | 80.0 MHz | FAIL | -1.634 ns |
| 10.0 ns | 100.0 MHz | FAIL | -4.130 ns |

50 MHz and 66.7 MHz are synthesis-clean. 80 MHz and 100 MHz still fail at synthesis.

## Verification Status

The sequential architecture is functionally verified:

- `tb_debug_vector2_seq_vs_ref` passed exact comparison.
- `tb_mimo_detector_top_seq_vectors` passed all 100 Phase 6 vectors.
- Tests remained exact after the Step 8.9 divider replacement.

No simulation tolerance was loosened.

## Next Step

The next step is implementation/place-and-route at 50 MHz first.

Start with the 20 ns clock because it has positive synthesis slack and gives place-and-route margin. Only after 50 MHz implementation succeeds should the design be tried at 66.7 MHz.

Do not claim board implementation success until post-route timing and implementation reports are available.
