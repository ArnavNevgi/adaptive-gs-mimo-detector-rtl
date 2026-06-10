# Area Optimization Plan

## Status

The area optimization work has moved from planning to measured Phase 8 results.

The verified unrolled RTL in `rtl/` remains the golden functional baseline. The optimized sequential RTL in `rtl_seq/` is now the FPGA synthesis candidate.

## Problem With The Unrolled Baseline

The unrolled baseline RTL passed functional verification, but it mapped too much arithmetic into one hardware instance:

- Parallel Gram matrix computation
- Parallel matched-filter computation
- Wide fixed-point arithmetic chains
- Behavioral division in the GS solver
- Low register count relative to logic count

On `xc7a35tcpg236-1`, this exceeded available logic and carry resources.

| Design | LUTs | FFs | DSPs | Timing | Outcome |
| --- | ---: | ---: | ---: | ---: | --- |
| `rtl/` unrolled baseline | 116,619 / 20,800 = 560.67% | 374 / 41,600 = 0.90% | 90 / 90 = 100% | WNS about -189.965 ns | Placement failed due to over-utilization |

The unrolled design is still valuable. It is the verified reference used to validate the optimized architecture, but it is not a feasible implementation for this target FPGA.

## Sequential Resource Sharing

Phase 8 introduced `rtl_seq/`, a sequential resource-shared architecture.

Resource sharing changes the hardware schedule, not the detector algorithm:

- One sequential Gram matrix engine replaces broad parallel Gram logic.
- One sequential matched-filter engine replaces broad parallel matched-filter logic.
- Regularization and metric accumulation are sequenced.
- The GS solver reuses update arithmetic across stream index and iteration count.
- Top-level control is handled by `mimo_detector_top_seq`.

This trades latency for area. That is the intended optimization for the Artix-7 target.

## Step 8.9 Timing Optimization

The first sequential synthesis fit in area but failed timing badly.

Root cause:

- `rtl_seq/gs_solver_seq.sv` still contained behavioral division.
- Vivado synthesized `/` as a large combinational divider.
- The critical path passed through GS division logic and into solver output registers.

Step 8.9 added `rtl_seq/signed_divider_seq.sv` and changed `gs_solver_seq` to use divider start/wait states. The divider is multi-cycle, signed, and bit-exact with the old quotient behavior.

## Utilization And Timing Comparison

| Design point | LUTs | FFs | DSPs | BRAM | CARRY4 | WNS | Data path delay |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Unrolled baseline RTL | 116,619 / 20,800 = 560.67% | 374 / 41,600 = 0.90% | 90 / 90 = 100% | Not limiting | Not reported here | about -189.965 ns | Not reported here |
| Sequential before divider fix | 15,561 / 20,800 = 74.81% | 2,127 / 41,600 = 5.11% | 12 / 90 = 13.33% | 0 / 50 = 0.00% | 3,632 | -173.984 ns | 183.929 ns |
| Sequential after `signed_divider_seq` | 3,024 / 20,800 = 14.54% | 2,289 / 41,600 = 5.50% | 12 / 90 = 13.33% | 0 / 50 = 0.00% | 255 | -4.130 ns at 10 ns | about 14.075 ns |

The divider fix sharply reduced LUT and carry-chain usage because Vivado no longer had to build a wide combinational divider in the GS update cycle.

These are synthesis results, not post-route implementation results.

## Clock Sweep After Divider Fix

| Clock period | Frequency | Synthesis result | WNS |
| ---: | ---: | --- | ---: |
| 20.0 ns | 50.0 MHz | PASS | +5.918 ns |
| 15.0 ns | 66.7 MHz | PASS | +0.918 ns |
| 12.5 ns | 80.0 MHz | FAIL | -1.634 ns |
| 10.0 ns | 100.0 MHz | FAIL | -4.130 ns |

50 MHz and 66.7 MHz are synthesis-clean. 80 MHz and 100 MHz still fail at synthesis.

## Verification Guardrails

The optimization must preserve exact RTL behavior against the Phase 6 vector set.

Current status:

- Baseline unrolled RTL passed the 100-vector Python-to-RTL verification.
- Sequential top passed all 100 Phase 6 vectors bit-exactly.
- Step 8.9 divider replacement kept exact simulation checks.
- No test tolerance was loosened.

## Next Implementation Plan

1. Run implementation/place-and-route at 50 MHz first.
2. Review post-route utilization, timing, and routing congestion.
3. If 50 MHz closes, try 66.7 MHz.
4. Keep 80 MHz and 100 MHz as later optimization targets, because they still fail at synthesis.

The project should not claim board implementation completion until post-route timing is clean and implementation reports have been reviewed.
