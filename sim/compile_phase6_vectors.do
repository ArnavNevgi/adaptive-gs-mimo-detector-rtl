transcript on

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

# RTL files
vlog -sv +incdir+rtl rtl/fixed_point_pkg.sv
vlog -sv +incdir+rtl rtl/complex_add.sv
vlog -sv +incdir+rtl rtl/complex_sub.sv
vlog -sv +incdir+rtl rtl/complex_mult.sv
vlog -sv +incdir+rtl rtl/complex_mac.sv
vlog -sv +incdir+rtl rtl/mode_select_unit.sv
vlog -sv +incdir+rtl rtl/condition_metric_unit.sv
vlog -sv +incdir+rtl rtl/gram_matrix_compute.sv
vlog -sv +incdir+rtl rtl/matched_filter_compute.sv
vlog -sv +incdir+rtl rtl/regularization_unit.sv
vlog -sv +incdir+rtl rtl/gs_solver.sv
vlog -sv +incdir+rtl rtl/x_to_xout_converter.sv
vlog -sv +incdir+rtl rtl/qpsk_slicer.sv
vlog -sv +incdir+rtl rtl/qpsk_slicer_array.sv
vlog -sv +incdir+rtl rtl/mimo_detector_top.sv

# Phase 6 vector package and testbench
vlog -sv +incdir+rtl +incdir+tb tb/phase6_vectors_pkg.sv
vlog -sv +incdir+rtl +incdir+tb tb/tb_mimo_detector_top_vectors.sv

vsim -c tb_mimo_detector_top_vectors -do "run -all; quit"

quit
