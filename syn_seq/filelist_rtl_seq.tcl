# RTL file list for Phase 8 sequential Vivado synthesis.
# Keep fixed_point_pkg.sv first and the flattened synthesis wrapper last.
# This list targets the optimized sequential, resource-shared architecture.

set rtl_seq_files [list \
    rtl/fixed_point_pkg.sv \
    rtl/mode_select_unit.sv \
    rtl/x_to_xout_converter.sv \
    rtl/qpsk_slicer_array.sv \
    rtl_seq/gram_matrix_seq.sv \
    rtl_seq/matched_filter_seq.sv \
    rtl_seq/regularization_metric_seq.sv \
    rtl_seq/gs_solver_seq.sv \
    rtl_seq/mimo_detector_top_seq.sv \
    rtl_seq/mimo_detector_top_seq_synth_wrapper.sv \
]

set default_synth_top mimo_detector_top_seq_synth_wrapper
