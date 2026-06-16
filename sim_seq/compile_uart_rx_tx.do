transcript on

onbreak {quit -code 1}
onerror {quit -code 1}

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb +incdir+tb_seq rtl_seq/uart_tx.sv
vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb +incdir+tb_seq rtl_seq/uart_rx.sv
vlog -sv +incdir+rtl +incdir+rtl_seq +incdir+tb +incdir+tb_seq tb_seq/tb_uart_rx_tx.sv

vsim -voptargs=+acc work.tb_uart_rx_tx

run -all
quit -code 0
