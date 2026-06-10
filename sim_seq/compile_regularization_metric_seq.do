transcript on

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -sv +incdir+rtl +incdir+rtl_seq rtl/fixed_point_pkg.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl/regularization_unit.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl/condition_metric_unit.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl_seq/regularization_metric_seq.sv
vlog -sv +incdir+rtl +incdir+rtl_seq tb_seq/tb_regularization_metric_seq.sv

vsim -voptargs=+acc work.tb_regularization_metric_seq

run -all