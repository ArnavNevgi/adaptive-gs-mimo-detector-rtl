transcript on

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -sv +incdir+rtl +incdir+rtl_seq rtl/fixed_point_pkg.sv

# Existing lightweight/reference RTL reused by sequential top
vlog -sv +incdir+rtl +incdir+rtl_seq rtl/mode_select_unit.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl/x_to_xout_converter.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl/qpsk_slicer_array.sv

# Sequential engines
vlog -sv +incdir+rtl +incdir+rtl_seq rtl_seq/gram_matrix_seq.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl_seq/matched_filter_seq.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl_seq/regularization_metric_seq.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl_seq/gs_solver_seq.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl_seq/mimo_detector_top_seq.sv

# Basic top-level testbench
vlog -sv +incdir+rtl +incdir+rtl_seq tb_seq/tb_mimo_detector_top_seq_basic.sv

vsim -voptargs=+acc work.tb_mimo_detector_top_seq_basic

run -all