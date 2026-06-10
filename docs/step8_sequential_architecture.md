# Step 8: Sequential Resource-Shared RTL Architecture

## Goal

Convert the verified unrolled RTL MIMO detector into an area-optimized sequential FPGA architecture.

The current unrolled RTL is functionally correct and passed 100 Python-generated vectors, but Vivado showed that it is too large for the Artix-7 xc7a35t FPGA.

## Baseline Status

Phase 6 result:
- Top-level RTL vector verification passed.
- 100 / 100 Python-generated vectors passed.
- Errors: 0
- Warnings: 0

Phase 7 result:
- Vivado synthesis passed.
- Vivado optimization passed.
- Placement failed due to over-utilization.

Post-opt baseline utilization on xc7a35tcpg236-1:
- Slice LUTs: 112,285 / 20,800 = 539.83%
- Slice Registers: 374 / 41,600 = 0.90%
- DSPs: 90 / 90 = 100%
- CARRY4: 23,715
- IOB: 809 / 106 = 763.21%

## Problem

The current RTL is a verified functional baseline, but it is too parallel and combinational.

Main issues:
1. Full combinational Gram matrix computation.
2. Full combinational matched filter computation.
3. Behavioral division inside GS solver.
4. Multiple arithmetic paths inferred in parallel.
5. Very low register usage.
6. Excessive top-level I/O due to flattened synthesis wrapper.

## Step 8 Design Principle

Preserve:
- Q formats
- Adaptive GS policy
- Condition metric
- QPSK bit mapping
- Python Phase 6 vector flow
- Existing unrolled RTL baseline

Change:
- Architecture only
- Use FSM control
- Reuse arithmetic datapaths over multiple cycles
- Increase registers
- Reduce LUT/DSP/CARRY usage

## Sequential Top-Level Flow

1. IDLE
2. LOAD_INPUTS
3. COMPUTE_G
4. COMPUTE_B
5. REGULARIZE_W
6. COMPUTE_METRIC
7. MODE_SELECT
8. GS_INIT
9. GS_ITERATE
10. XOUT_CONVERT
11. SLICE_BITS
12. DONE

## New RTL Files

New optimized files will be created under rtl_seq/.

Planned modules:
1. gram_matrix_seq.sv
2. matched_filter_seq.sv
3. regularization_metric_seq.sv
4. gs_solver_seq.sv
5. mimo_detector_top_seq.sv

## Verification Plan

Each sequential module will first be verified against the existing unrolled module.

Module-level tests:
1. gram_matrix_seq vs gram_matrix_compute
2. matched_filter_seq vs matched_filter_compute
3. gs_solver_seq vs gs_solver
4. mimo_detector_top_seq vs Phase 6 vector package

Final sequential top must match:
- mode
- num_iters
- xout_re
- xout_im
- bits

## Synthesis Goal

Compare sequential design against unrolled baseline.

Unrolled baseline:
- LUTs: about 112k
- DSPs: 90
- Registers: 374
- Placement: failed on xc7a35t

Sequential target:
- Much lower LUT usage
- Lower or controlled DSP usage
- Higher register usage
- Placement should become feasible
- Higher latency is acceptable

## First Implementation Target

Start with sequential Gram matrix engine.

Equation:

G = H^H H

For each entry:

G[i][j] = sum over r of conj(H[r][i]) * H[r][j]

For 4x4:
- 16 G entries
- 4 terms per entry
- 64 complex MAC operations

Instead of computing these in parallel, use one reused complex multiply-accumulate datapath controlled by counters.

## Permanent RTL Organization

This project keeps two RTL architecture trees permanently.

### rtl/

The `rtl/` directory contains the original verified unrolled RTL baseline.

Purpose:
- Golden functional reference
- Phase 5/Phase 6 verified design
- Used for module-by-module comparison against optimized RTL
- Used to document the first hardware implementation attempt

This architecture is more parallel and combinational. It is useful for correctness validation but was too large for the target FPGA after synthesis.

### rtl_seq/

The `rtl_seq/` directory contains the Phase 8 sequential resource-shared architecture.

Purpose:
- Area-optimized FPGA architecture
- Reuses arithmetic datapaths across cycles
- Reduces LUT/DSP/carry-chain pressure
- Trades latency for resource efficiency
- Used for final synthesis comparison against the unrolled baseline

### Research Value

Keeping both architectures allows the project to report a clear design progression:

1. Verified fixed-point algorithm
2. Unrolled functional RTL baseline
3. FPGA synthesis bottleneck analysis
4. Sequential resource-shared RTL redesign
5. Area/timing comparison between both architectures

This makes the project stronger because it demonstrates not only correctness, but also hardware architecture optimization.