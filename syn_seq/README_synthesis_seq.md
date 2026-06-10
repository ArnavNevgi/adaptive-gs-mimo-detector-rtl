# Phase 8 Sequential Vivado Synthesis

This folder contains Vivado synthesis support for the optimized sequential, resource-shared 4x4 adaptive GS fixed-point MIMO detector.

## Target

- Device: `xc7a35tcpg236-1`
- Functional top: `mimo_detector_top_seq`
- Default synthesis top: `mimo_detector_top_seq_synth_wrapper`
- Clock: `clk`
- Default clock period: `10 ns` / `100 MHz`
- Flow: synthesis only, out-of-context by default

The wrapper is synthesis-facing only. It flattens unpacked-array ports into 1-D buses for Vivado and instantiates the verified `rtl_seq/mimo_detector_top_seq` internally. It does not change detector behavior.

## Run

From the project root:

```tcl
vivado -mode batch -source syn_seq/vivado_synth_seq.tcl
```

Optional arguments:

```tcl
vivado -mode batch -source syn_seq/vivado_synth_seq.tcl -tclargs -top mimo_detector_top_seq_synth_wrapper
vivado -mode batch -source syn_seq/vivado_synth_seq.tcl -tclargs -part xc7a35tcpg236-1
vivado -mode batch -source syn_seq/vivado_synth_seq.tcl -tclargs -clock_period 10.000
vivado -mode batch -source syn_seq/vivado_synth_seq.tcl -tclargs -no_ooc
```

## RTL Sources

`filelist_rtl_seq.tcl` includes:

- `rtl/fixed_point_pkg.sv`
- `rtl/mode_select_unit.sv`
- `rtl/x_to_xout_converter.sv`
- `rtl/qpsk_slicer_array.sv`
- `rtl_seq/gram_matrix_seq.sv`
- `rtl_seq/matched_filter_seq.sv`
- `rtl_seq/regularization_metric_seq.sv`
- `rtl_seq/gs_solver_seq.sv`
- `rtl_seq/mimo_detector_top_seq.sv`
- `rtl_seq/mimo_detector_top_seq_synth_wrapper.sv`

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

The wrapper also exposes scalar control/status ports: `clk`, `rst_n`, `start`, `snr_level`, `noise_var`, `done`, `busy`, `mode`, and `num_iters`.

## Reports

Vivado writes synthesis outputs to:

- `results/phase8_synthesis_seq/utilization_seq.rpt`
- `results/phase8_synthesis_seq/timing_seq.rpt`
- `results/phase8_synthesis_seq/power_seq.rpt` if Vivado can estimate power at this stage
- `results/phase8_synthesis_seq/synth_seq.dcp`

The script creates `results/phase8_synthesis_seq/` if it does not already exist. It also writes a generated `clock_seq.xdc` there for the `clk` timing constraint.

## Notes

- This flow does not run implementation. Run opt/place/route only after synthesis succeeds cleanly.
- The default wrapper top avoids Vivado top-level issues with unpacked arrays and package enum ports.
- The sequential RTL is the resource-shared Phase 8 architecture, not the older unrolled `rtl/` baseline.
