transcript on

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb rtl/fixed_point_pkg.sv
vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb tb/phase6_vectors_pkg.sv

# Baseline/reference RTL
vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb rtl/gram_matrix_compute.sv
vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb rtl/matched_filter_compute.sv
vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb rtl/regularization_unit.sv
vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb rtl/condition_metric_unit.sv
vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb rtl/gs_solver.sv
vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb rtl/x_to_xout_converter.sv

# Sequential RTL
vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb rtl_seq/gram_matrix_seq.sv
vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb rtl_seq/matched_filter_seq.sv
vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb rtl_seq/regularization_metric_seq.sv
vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb rtl_seq/signed_divider_seq.sv
vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb rtl_seq/gs_solver_seq.sv

# Focused vector-2 seq-vs-ref debug testbench
vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb tb_seq/tb_debug_vector2_seq_vs_ref.sv

vsim -voptargs=+acc work.tb_debug_vector2_seq_vs_ref

run -all
