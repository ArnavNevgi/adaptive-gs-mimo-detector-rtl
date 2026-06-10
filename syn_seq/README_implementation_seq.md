# Phase 8 Sequential Implementation

This folder contains the Vivado implementation flow for the optimized sequential/resource-shared MIMO detector.

## Target

- Device: `xc7a35tcpg236-1`
- Top: `mimo_detector_top_seq_impl_wrapper`
- Default clock period: `20.000 ns` / `50 MHz`
- RTL filelist: `syn_seq/filelist_rtl_seq.tcl`
- Include directories:
  - `rtl/`
  - `rtl_seq/`

The implementation script uses the same RTL source list as sequential synthesis, then runs:

1. `synth_design`
2. `opt_design`
3. `place_design`
4. `phys_opt_design`
5. `route_design`

It writes a bitstream only after routing succeeds.

## Implementation Wrapper

Implementation uses `rtl_seq/mimo_detector_top_seq_impl_wrapper.sv`, not the flattened synthesis wrapper.

The flattened synthesis wrapper exposes the full detector input/output vectors and creates 810 top-level I/O ports. That is useful for synthesis analysis, but it cannot be placed in the `xc7a35tcpg236` package, which has 106 usable user I/O pins.

The implementation wrapper keeps the verified `mimo_detector_top_seq` core intact and exposes a compact host-style register interface:

- `host_wr_en`
- `host_wr_addr[5:0]`
- `host_wr_data[19:0]`
- `host_rd_addr[5:0]`
- `host_rd_data[19:0]`
- scalar control/status ports

This wrapper is for package-level place-and-route and bitstream generation. It is not a new detector algorithm.

## Run From Vivado GUI Tcl

From the project root in the Vivado Tcl console:

```tcl
close_project
set argv [list -clock_period 20.000]
source syn_seq/vivado_impl_seq.tcl
```

To try the 66.7 MHz synthesis-clean target:

```tcl
close_project
set argv [list -clock_period 15.000]
source syn_seq/vivado_impl_seq.tcl
```

## Run In Batch

From the project root:

```tcl
vivado -mode batch -source syn_seq/vivado_impl_seq.tcl -tclargs -clock_period 20.000
```

For 15 ns:

```tcl
vivado -mode batch -source syn_seq/vivado_impl_seq.tcl -tclargs -clock_period 15.000
```

## Outputs

For clock period `20.000`, reports are written to:

- `results/phase8_impl_seq/clk_20p000ns/utilization_impl.rpt`
- `results/phase8_impl_seq/clk_20p000ns/timing_impl.rpt`
- `results/phase8_impl_seq/clk_20p000ns/power_impl.rpt`
- `results/phase8_impl_seq/clk_20p000ns/route_status.rpt`
- `results/phase8_impl_seq/clk_20p000ns/routed_impl.dcp`
- `results/phase8_impl_seq/clk_20p000ns/mimo_detector_top_seq.bit` if routing succeeds

For clock period `15.000`, replace `clk_20p000ns` with `clk_15p000ns`.

The script also writes `clock_impl.xdc` into the clock-specific result directory.

## Current Strategy

Start with 20 ns / 50 MHz because synthesis has positive slack at that target:

| Clock period | Frequency | Synthesis result | WNS |
| ---: | ---: | --- | ---: |
| 20.0 ns | 50.0 MHz | PASS | +5.918 ns |
| 15.0 ns | 66.7 MHz | PASS | +0.918 ns |
| 12.5 ns | 80.0 MHz | FAIL | -1.634 ns |
| 10.0 ns | 100.0 MHz | FAIL | -4.130 ns |

These are synthesis timing results. Implementation/place-and-route timing must be reviewed separately before claiming hardware closure.

## Notes

- If a stage fails, the script writes whatever reports Vivado can produce before stopping.
- The bitstream is not generated unless `route_design` succeeds.
- A routed checkpoint can be produced without board pin assignments, but bitstream generation requires LOC and IOSTANDARD constraints for the implementation wrapper ports.
- Do not treat a generated bitstream as board validation. Board-level constraints and post-route timing still need review.
