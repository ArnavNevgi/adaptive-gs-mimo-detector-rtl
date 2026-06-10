# RTL file list for Step 7 Vivado synthesis.
# Keep fixed_point_pkg.sv first and the synthesis wrapper last.

set rtl_files [list \
    rtl/fixed_point_pkg.sv \
    rtl/complex_add.sv \
    rtl/complex_sub.sv \
    rtl/complex_mult.sv \
    rtl/complex_mac.sv \
    rtl/mode_select_unit.sv \
    rtl/condition_metric_unit.sv \
    rtl/gram_matrix_compute.sv \
    rtl/matched_filter_compute.sv \
    rtl/regularization_unit.sv \
    rtl/gs_solver.sv \
    rtl/x_to_xout_converter.sv \
    rtl/qpsk_slicer.sv \
    rtl/qpsk_slicer_array.sv \
    rtl/mimo_detector_top.sv \
    rtl/mimo_detector_top_synth_wrapper.sv \
]

set default_synth_top mimo_detector_top_synth_wrapper
