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

# Testbenches
vlog -sv +incdir+rtl tb/tb_mode_select_unit.sv
vlog -sv +incdir+rtl tb/tb_qpsk_slicer.sv
vlog -sv +incdir+rtl tb/tb_complex_mult.sv
vlog -sv +incdir+rtl tb/tb_complex_mac.sv
vlog -sv +incdir+rtl tb/tb_condition_metric_unit.sv
vlog -sv +incdir+rtl tb/tb_gram_matrix_compute.sv
vlog -sv +incdir+rtl tb/tb_matched_filter_compute.sv
vlog -sv +incdir+rtl tb/tb_regularization_unit.sv
vlog -sv +incdir+rtl tb/tb_gs_solver.sv
vlog -sv +incdir+rtl tb/tb_x_to_xout_converter.sv
vlog -sv +incdir+rtl tb/tb_qpsk_slicer_array.sv
vlog -sv +incdir+rtl tb/tb_solver_slicer_chain.sv
vlog -sv +incdir+rtl tb/tb_mimo_detector_top.sv

# Simulations
vsim -c tb_mode_select_unit -do "run -all; quit"
vsim -c tb_qpsk_slicer -do "run -all; quit"
vsim -c tb_complex_mult -do "run -all; quit"
vsim -c tb_complex_mac -do "run -all; quit"
vsim -c tb_condition_metric_unit -do "run -all; quit"
vsim -c tb_gram_matrix_compute -do "run -all; quit"
vsim -c tb_matched_filter_compute -do "run -all; quit"
vsim -c tb_regularization_unit -do "run -all; quit"
vsim -c tb_gs_solver -do "run -all; quit"
vsim -c tb_x_to_xout_converter -do "run -all; quit"
vsim -c tb_qpsk_slicer_array -do "run -all; quit"
vsim -c tb_solver_slicer_chain -do "run -all; quit"
vsim -c tb_mimo_detector_top -do "run -all; quit"

quit