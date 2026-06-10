# Step 7 Vivado Synthesis Notes

This folder contains the first Vivado synthesis flow for the verified 4x4 adaptive GS fixed-point MIMO detector.

## Target

- Device: `xc7a35tcpg236-1`
- Optional larger exploratory device: `xc7a200tfbg484-2`
- Functional top: `mimo_detector_top`
- Default synthesis top: `mimo_detector_top_synth_wrapper`
- Clock: `clk`
- Clock period: `10 ns` / `100 MHz`

The wrapper is synthesis-facing only. It flattens unpacked-array ports into 1-D buses for Vivado and instantiates the verified `mimo_detector_top` internally. It does not change detector behavior.

## Port Flattening

Wrapper index mapping:

- `H` index: `r*NT + c`
- `y` index: `r`
- `xout` index: `i`
- `bits` index: `i`

Flattened widths:

- `H_re_flat`, `H_im_flat`: `NR*NT*H_W`
- `y_re_flat`, `y_im_flat`: `NR*Y_W`
- `xout_re_flat`, `xout_im_flat`: `NT*XOUT_W`
- `bits_flat`: `NT*2`

## Run

From the project root:

```tcl
vivado -mode batch -source syn/vivado_synth.tcl
```

To run the exploratory larger part:

```tcl
vivado -mode batch -source syn/vivado_synth.tcl -tclargs -part xc7a200tfbg484-2
```

To try the direct unpacked-array top instead:

```tcl
vivado -mode batch -source syn/vivado_synth.tcl -tclargs -top mimo_detector_top
```

## Reports

Vivado writes:

- `syn/reports/utilization_post_synth.rpt`
- `syn/reports/timing_post_synth.rpt`
- `syn/reports/mimo_detector_top_post_synth.dcp`
- `syn/reports/utilization_post_opt.rpt`
- `syn/reports/utilization.rpt`
- `syn/reports/timing_summary.rpt`
- `syn/reports/power.rpt`
- `syn/reports/drc.rpt`

If placement fails, post-synthesis and post-opt reports are still generated. The script does not suppress over-utilization DRC and does not set `drc.disableLUTOverUtilError`.

If routing completes, Vivado also writes:

- `syn/reports/mimo_detector_top_routed.dcp`

## Current Step 7 Result

For the default target `xc7a35tcpg236-1`, Vivado synthesis succeeds, but implementation fails at `place_design` due to over-utilization.

Reported DRC/resource pressure:

- `CARRY4` required: `23715`, available: `8150`
- `LUT as Logic` required: `112285`, available: `20800`
- `LUT6` required: `38938`, available: `32600`

This means the current RTL is a verified functional baseline, not yet an area-optimized Artix-7 implementation.

Likely contributors:

- Full combinational Gram matrix compute
- Full combinational matched filter compute
- Behavioral division in `gs_solver`
- Multiple inferred dividers
- Wide fixed-point arithmetic

Conclusion: an area-optimized architecture is needed for `xc7a35t`.

## Notes

- The GS solver still uses behavioral division. This is intentional for Step 7 and may infer large logic.
- Internal paths intentionally keep the current truncation/wrap behavior.
- The condition metric intentionally uses `abs(re) + abs(im)` to match the verified RTL.
- Do not compare this synthesis RTL against floating-point MMSE for Step 7; Phase 6 equivalence is the reference.
