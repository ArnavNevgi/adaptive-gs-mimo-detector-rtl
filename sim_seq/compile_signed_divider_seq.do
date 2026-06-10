transcript on

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -sv +incdir+rtl +incdir+rtl_seq rtl_seq/signed_divider_seq.sv
vlog -sv +incdir+rtl +incdir+rtl_seq tb_seq/tb_signed_divider_seq.sv

vsim -voptargs=+acc work.tb_signed_divider_seq

run -all
