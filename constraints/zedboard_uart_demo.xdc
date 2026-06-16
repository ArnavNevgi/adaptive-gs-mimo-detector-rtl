# ZedBoard PL-only UART demo constraints for zedboard_mimo_uart_top.
#
# Important board note:
# The onboard ZedBoard USB-UART bridge is wired to Zynq PS MIO pins, not normal
# PL package pins listed in the public ZedBoard master XDC. A pure-PL UART top
# cannot directly LOC those PS MIO pins. This PL-only demo therefore uses an
# external 3.3 V USB-UART adapter connected to JA Pmod pins from the official
# ZedBoard XDC:
#   JA1 Y11: adapter TX -> FPGA uart_rx_i
#   JA2 AA11: FPGA uart_tx_o -> adapter RX
#   GND: adapter GND -> ZedBoard Pmod GND
#
# Clock/reset/LED LOCs also follow the public ZedBoard master XDC.

set_property PACKAGE_PIN Y9 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name zedboard_gclk [get_ports clk]

set_property PACKAGE_PIN P16 [get_ports rst_btn]
set_property IOSTANDARD LVCMOS18 [get_ports rst_btn]

set_property PACKAGE_PIN Y11 [get_ports uart_rx_i]
set_property PACKAGE_PIN AA11 [get_ports uart_tx_o]
set_property IOSTANDARD LVCMOS33 [get_ports {uart_rx_i uart_tx_o}]

set_property PACKAGE_PIN T22 [get_ports {led[0]}]
set_property PACKAGE_PIN T21 [get_ports {led[1]}]
set_property PACKAGE_PIN U22 [get_ports {led[2]}]
set_property PACKAGE_PIN U21 [get_ports {led[3]}]
set_property PACKAGE_PIN V22 [get_ports {led[4]}]
set_property PACKAGE_PIN W22 [get_ports {led[5]}]
set_property PACKAGE_PIN U19 [get_ports {led[6]}]
set_property PACKAGE_PIN U14 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
