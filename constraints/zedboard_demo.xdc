# ZedBoard board-demo constraints for zedboard_mimo_demo_top.
#
# Pin LOCs follow the public ZedBoard master XDC naming:
#   GCLK: Y9
#   BTNC: P16, BTNU: T18
#   SW0: F22, SW1: G22
#   LD0..LD7: T22, T21, U22, U21, V22, W22, U19, U14
#
# TODO: Confirm these LOCs and the Bank 34/35 Vadj IOSTANDARD settings against
# the official ZedBoard master XDC for the exact board revision before using
# this bitstream on hardware. ZedBoard Bank 13 and Bank 33 are fixed at 3.3 V;
# Bank 34 and Bank 35 are commonly 1.8 V by default.

set_property PACKAGE_PIN Y9 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name zedboard_gclk [get_ports clk]

set_property PACKAGE_PIN P16 [get_ports rst_btn]
set_property PACKAGE_PIN T18 [get_ports start_btn]
set_property IOSTANDARD LVCMOS18 [get_ports {rst_btn start_btn}]

set_property PACKAGE_PIN F22 [get_ports start_sw]
set_property PACKAGE_PIN G22 [get_ports display_sw]
set_property IOSTANDARD LVCMOS18 [get_ports {start_sw display_sw}]

set_property PACKAGE_PIN T22 [get_ports {led[0]}]
set_property PACKAGE_PIN T21 [get_ports {led[1]}]
set_property PACKAGE_PIN U22 [get_ports {led[2]}]
set_property PACKAGE_PIN U21 [get_ports {led[3]}]
set_property PACKAGE_PIN V22 [get_ports {led[4]}]
set_property PACKAGE_PIN W22 [get_ports {led[5]}]
set_property PACKAGE_PIN U19 [get_ports {led[6]}]
set_property PACKAGE_PIN U14 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
