transcript on

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -sv +incdir+rtl +incdir+rtl_seq rtl/fixed_point_pkg.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl/gs_solver.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl_seq/signed_divider_seq.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl_seq/gs_solver_seq.sv
vlog -sv +incdir+rtl +incdir+rtl_seq tb_seq/tb_gs_solver_seq.sv

vsim -voptargs=+acc work.tb_gs_solver_seq

run -all
