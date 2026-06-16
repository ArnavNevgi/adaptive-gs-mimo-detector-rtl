# ZedBoard Bring-Up Demo

This demo is the first simple board path for the verified sequential MIMO detector. It targets the ZedBoard Zynq-7000 part `xc7z020clg484-1` and top module `zedboard_mimo_demo_top`.

The FPGA wrapper hardcodes one known QPSK test:

- `H = identity`
- `y = [+1+j, -1+j, -1-j, +1-j]`
- `noise_var = 0`
- `snr_level = high`

Expected result:

- mode: `GS4`, encoded as `00`
- detected QPSK bits: `00, 01, 11, 10`

## Board Connections

1. Connect the ZedBoard power supply and turn the board on.
2. Connect the PC to the ZedBoard USB-JTAG programming port.
3. Leave the design using the PL 100 MHz board clock.
4. Use BTNC as reset.
5. Use BTNU or SW0 as start.
6. Use SW1 to select what the LEDs show.

Check `constraints/zedboard_demo.xdc` against the official ZedBoard master XDC for your exact board revision before programming hardware. The demo uses real LOC and IOSTANDARD constraints, but Bank 34 and Bank 35 depend on the board Vadj setting.

## Build The Bitstream

From Vivado batch mode:

```tcl
vivado -mode batch -source syn_seq/vivado_impl_zedboard_demo.tcl
```

From the Vivado Tcl console:

```tcl
cd C:/fpga_projects/adaptive-gs-mimo-detector
close_project
source syn_seq/vivado_impl_zedboard_demo.tcl
```

Outputs are written under:

```text
results/phase8_zedboard_demo/clk_20p000ns/
```

The expected bitstream path is:

```text
results/phase8_zedboard_demo/clk_20p000ns/zedboard_mimo_demo_top.bit
```

## Program The Board

In Vivado:

1. Open Hardware Manager.
2. Click Open Target, then Auto Connect.
3. Select the detected `xc7z020` device.
4. Program it with `results/phase8_zedboard_demo/clk_20p000ns/zedboard_mimo_demo_top.bit`.

Equivalent Vivado Tcl:

```tcl
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices] 0]
set_property PROGRAM.FILE {C:/fpga_projects/adaptive-gs-mimo-detector/results/phase8_zedboard_demo/clk_20p000ns/zedboard_mimo_demo_top.bit} $dev
program_hw_devices $dev
```

## Run The Demo

1. Press BTNC once to reset.
2. Put SW1 low to view status LEDs.
3. Press BTNU once, or toggle SW0 from low to high, to start the detector.
4. LD1 turns on while the detector is busy.
5. LD0 turns on after the result is latched.
6. LD3:LD2 show the latched mode. For this test, both are off because `GS4 = 00`.
7. LD4 blinks as a heartbeat while the 50 MHz detector clock is running.
8. Put SW1 high to view detected bits.

On the bits page:

```text
LD1:LD0 = stream 0 bits = 00
LD3:LD2 = stream 1 bits = 01
LD5:LD4 = stream 2 bits = 11
LD7:LD6 = stream 3 bits = 10
```

Reading the LEDs from LD7 down to LD0, the expected pattern is:

```text
10_11_01_00
```

## If Hardware Manager Does Not Detect The Board

1. Confirm the board is powered on and the power-good LED is lit.
2. Confirm the USB cable is plugged into the USB-JTAG programming connector, not only a power-only USB port.
3. Try a known data-capable USB cable and a direct PC USB port.
4. Install or repair the Vivado cable drivers, then restart Vivado.
5. In Hardware Manager, close the target and try Open Target, Auto Connect again.
6. If the JTAG chain is still missing, check the ZedBoard boot-mode and jumper settings against the ZedBoard user guide, then power-cycle the board.
7. Try lowering variables: disconnect extra peripherals and test with only power plus USB-JTAG connected.
