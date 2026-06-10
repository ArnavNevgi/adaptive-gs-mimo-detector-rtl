# Adaptive GS MIMO Detector

This project implements a 4x4 adaptive fixed-point Gauss-Seidel MIMO QPSK detector and tracks the design from algorithm model through RTL verification and FPGA synthesis.

## Project Structure

| Path | Purpose |
| --- | --- |
| `python/` | Floating-point and fixed-point modeling support |
| `vectors/` | Generated verification vectors |
| `rtl/` | Verified unrolled baseline RTL |
| `rtl_seq/` | Optimized sequential/resource-shared RTL |
| `tb/` | Phase 6 vector packages and baseline tests |
| `tb_seq/` | Sequential RTL tests |
| `sim/` | Baseline simulation scripts |
| `sim_seq/` | Sequential simulation scripts |
| `syn/` | Previous unrolled Vivado synthesis scripts/results |
| `syn_seq/` | Sequential Vivado synthesis flow |
| `docs/` | Architecture and optimization notes |

The `rtl/` and `rtl_seq/` directories are both intentional.

- `rtl/` is the verified unrolled functional baseline.
- `rtl_seq/` is the area-optimized sequential architecture used for the current FPGA synthesis path.

## Verification Status

Completed:

- Python floating-point detector model
- Adaptive GS iteration policy
- Fixed-point model
- Baseline unrolled RTL
- 100-vector Python-to-RTL verification
- Sequential/resource-shared RTL
- Sequential top verification across all 100 Phase 6 vectors
- Step 8.9 replacement of behavioral GS division with `signed_divider_seq`

The sequential RTL has passed the Phase 6 vector set bit-exactly. Simulation checks were not loosened.

## Architecture Progression

The first RTL architecture in `rtl/` was deliberately unrolled and parallel. It was useful for correctness, but not practical for the target Artix-7 device.

Unrolled baseline synthesis on `xc7a35tcpg236-1`:

| Metric | Result |
| --- | ---: |
| LUTs | 116,619 / 20,800 = 560.67% |
| FFs | 374 / 41,600 = 0.90% |
| DSPs | 90 / 90 = 100% |
| WNS | about -189.965 ns |
| Outcome | Placement failed due to over-utilization |

Phase 8 introduced `rtl_seq/`, which reuses arithmetic over multiple cycles. This reduced area enough to fit the synthesis target.

## Step 8.9 Divider Timing Fix

Sequential synthesis initially fit in area but failed timing because `gs_solver_seq` still used behavioral division. Vivado synthesized the `/` operator as a large combinational divider, producing a very long carry-chain path.

Step 8.9 added `rtl_seq/signed_divider_seq.sv`, a multi-cycle signed divider. This removed the combinational divider from the critical cycle while preserving bit-exact solver behavior.

| Design point | LUTs | FFs | DSPs | BRAM | CARRY4 | WNS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Sequential before divider fix | 15,561 / 20,800 = 74.81% | 2,127 / 41,600 = 5.11% | 12 / 90 = 13.33% | 0 / 50 = 0.00% | 3,632 | -173.984 ns |
| Sequential after divider fix | 3,024 / 20,800 = 14.54% | 2,289 / 41,600 = 5.50% | 12 / 90 = 13.33% | 0 / 50 = 0.00% | 255 | -4.130 ns at 10 ns |

These are synthesis timing results, not post-route timing results.

## Clock Sweep

After the divider fix:

| Clock period | Frequency | Synthesis result | WNS |
| ---: | ---: | --- | ---: |
| 20.0 ns | 50.0 MHz | PASS | +5.918 ns |
| 15.0 ns | 66.7 MHz | PASS | +0.918 ns |
| 12.5 ns | 80.0 MHz | FAIL | -1.634 ns |
| 10.0 ns | 100.0 MHz | FAIL | -4.130 ns |

50 MHz and 66.7 MHz are synthesis-clean. 80 MHz and 100 MHz still fail at synthesis.

## Current Synthesis Flow

Sequential synthesis is driven from `syn_seq/`:

```tcl
cd C:/fpga_projects/adaptive-gs-mimo-detector
source syn_seq/vivado_synth_seq.tcl
```

The default target is:

- Synthesis top: `mimo_detector_top_seq_synth_wrapper`
- Part: `xc7a35tcpg236-1`
- Clock: 10 ns unless overridden
- Flow: synthesis only, out-of-context by default

## Current Implementation Flow

Run implementation/place-and-route at 50 MHz first.

Vivado GUI Tcl:

```tcl
close_project
set argv [list -clock_period 20.000]
source syn_seq/vivado_impl_seq.tcl
```

Batch:

```tcl
vivado -mode batch -source syn_seq/vivado_impl_seq.tcl -tclargs -clock_period 20.000
```

The implementation flow defaults to top `mimo_detector_top_seq_impl_wrapper`, writes reports under `results/phase8_impl_seq/clk_20p000ns/`, and generates `mimo_detector_top_seq.bit` only after routing succeeds.

Implementation uses `mimo_detector_top_seq_impl_wrapper`, a compact host-register wrapper around the verified sequential core. The flattened synthesis wrapper has 810 top-level ports and is not package-placeable on the `cpg236` device.

## Next Step

The next step is implementation/place-and-route at 50 MHz first. The 20 ns synthesis result has positive slack and is the safest first implementation target.

Do not claim board implementation completion until post-route timing and implementation reports are available.

## More Details

- [Phase 8 Sequential Architecture](docs/phase8_sequential_architecture.md)
- [Area Optimization Plan](docs/area_optimization_plan.md)
- [Sequential Vivado Synthesis Notes](syn_seq/README_synthesis_seq.md)
- [Sequential Vivado Implementation Notes](syn_seq/README_implementation_seq.md)
