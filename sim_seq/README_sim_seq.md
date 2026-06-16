# Sequential RTL Simulation

The `sim_seq/` directory contains small QuestaSim scripts for focused sequential RTL tests, plus one full-regression script.

## Run One Test

Run an individual test from the repository root:

```tcl
vsim -do sim_seq/compile_gs_solver_seq.do
```

Use the matching script for the block you want to inspect, for example:

```tcl
vsim -do sim_seq/compile_signed_divider_seq.do
vsim -do sim_seq/compile_mimo_detector_top_seq_vectors.do
```

The individual scripts are intentionally kept because they are fast, focused, and useful while debugging one block. Each one recreates `work`, compiles the minimum set of files for that test, and leaves the simulator positioned at the failing design context if something needs inspection.

## Run Full Regression

Run the complete sequential regression from the repository root:

```tcl
vsim -do sim_seq/run_all_seq.do
```

`run_all_seq.do` computes the repository root from `[info script]`, changes to that root, recreates the `work` library once, compiles the shared RTL, sequential RTL, reference RTL, vector package when present, and all applicable `tb_seq` testbenches.

It then runs the tests in this order:

1. `tb_signed_divider_seq`
2. `tb_gram_matrix_seq`
3. `tb_matched_filter_seq`
4. `tb_regularization_metric_seq`
5. `tb_gs_solver_seq`
6. `tb_mimo_detector_top_seq_basic`
7. `tb_mimo_detector_top_seq_vectors`, when `tb/phase6_vectors_pkg.sv` exists
8. `tb_debug_vector2_seq_vs_ref`, when `tb/phase6_vectors_pkg.sv` exists

## Final Proof Script

The individual scripts prove one block at a time. `run_all_seq.do` is the final proof script because it compiles the current sequential RTL once in a clean library, runs the block-level checks, runs the full sequential top checks, and returns a nonzero process exit code on the first compile or simulation failure.
