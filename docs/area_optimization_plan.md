# Area Optimization Plan

## A. Problem Summary

The current Phase 5/6 RTL is functionally verified, but it is too parallel for the first Artix-7 synthesis target. Vivado synthesis succeeds, but implementation fails at `place_design` because the design exceeds the available logic and carry resources on `xc7a35tcpg236-1`.

The current RTL should be treated as a verified functional baseline. It is useful for algorithm-to-RTL equivalence, but it is not yet an area-optimized FPGA architecture.

## B. Current Resource Over-Utilization Numbers

Vivado DRC result for `xc7a35tcpg236-1`:

- `CARRY4` required: `23715`, available: `8150`
- `LUT as Logic` required: `112285`, available: `20800`
- `LUT6` required: `38938`, available: `32600`

## C. Likely Causes

- Fully combinational Gram matrix computation for all `G = H^H H` entries
- Fully combinational matched-filter computation for all `b = H^H y` entries
- Behavioral division in `gs_solver`
- Multiple inferred divider structures from diagonal initialization and GS updates
- Wide fixed-point arithmetic paths
- Large unrolled combinational datapaths with limited resource sharing

## D. Proposed Optimized Architecture

The optimized architecture should preserve the same external detector function and Step 6 reference behavior while reducing area through time-multiplexed datapaths.

Recommended structure:

- Sequential Gram matrix engine using a reusable complex MAC
- Sequential matched-filter engine using a reusable complex MAC
- GS solver with one update datapath reused across stream index `i` and iteration count
- Reciprocal LUT or reciprocal-multiply path replacing behavioral division
- FSM controller coordinating matrix build, regularization, condition metric, mode select, GS solve, xout conversion, and slicing
- Same adaptive modes: GS-4, GS-8, GS-16
- Same fixed-point formats and current RTL-equivalent arithmetic behavior unless explicitly retuned later

## E. Verification Plan

- Reuse the Phase 6 Python-to-RTL vector flow
- Keep `mimo_detector_top` functional RTL as the reference baseline
- Add an optimized top or wrapper only after the new architecture is implemented
- Compare:
  - mode
  - num_iters
  - xout
  - QPSK bits
- Start with the existing 100 vectors
- Expand vectors after the optimized architecture matches the functional baseline

## F. Expected Benefit

- Much lower LUT and CARRY usage through resource sharing
- Reduced inferred divider area after reciprocal replacement
- Lower combinational depth per cycle
- More cycles per frame and higher latency
- Same algorithmic behavior and same detector outputs within the agreed RTL-equivalent tolerance

## G. Implementation Status

Do not implement the optimized architecture yet unless explicitly requested.

The next step is to collect post-synthesis/post-opt reports from the current baseline, then use those reports to size the sequential engines and reciprocal strategy.
