transcript on

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -sv +incdir+rtl +incdir+rtl_seq rtl/fixed_point_pkg.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl/matched_filter_compute.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl_seq/matched_filter_seq.sv
vlog -sv +incdir+rtl +incdir+rtl_seq tb_seq/tb_matched_filter_seq.sv

vsim -voptargs=+acc work.tb_matched_filter_seq

run -all