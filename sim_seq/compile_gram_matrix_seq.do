transcript on

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -sv +incdir+rtl +incdir+rtl_seq rtl/fixed_point_pkg.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl/gram_matrix_compute.sv
vlog -sv +incdir+rtl +incdir+rtl_seq rtl_seq/gram_matrix_seq.sv
vlog -sv +incdir+rtl +incdir+rtl_seq tb_seq/tb_gram_matrix_seq.sv

vsim -voptargs=+acc work.tb_gram_matrix_seq

run -all