# ZedBoard PL UART MIMO Demo

This demo sends one fixed-point MIMO vector from a PC to the FPGA over a simple binary UART protocol. The PL logic loads the vector into the existing verified sequential adaptive GS MIMO detector, waits for `done`, then returns mode, iteration count, detected QPSK bits, and fixed-point detector outputs over UART. The Python host script compares the returned identity-vector bits against the expected `00 01 11 10` result.

This is a pure PL demo. It does not use AXI, Vitis, Linux, or Zynq PS software.

## Why This Exists

The first ZedBoard LED demo used one hardcoded identity vector inside the FPGA. That was a good bring-up step, but it could not accept new vectors at runtime.

The UART demo keeps the same verified sequential detector, but moves vector input and result checking to the PC. This makes it possible to send the identity vector now and later extend the host flow to send multiple test vectors without rebuilding the bitstream.

## Important UART Connection Note

The onboard ZedBoard USB-UART bridge is wired to Zynq PS MIO pins, not directly to PL package pins in the public ZedBoard master XDC. A pure PL UART cannot LOC those PS MIO pins.

For this PL-only demo, connect an external 3.3 V USB-UART adapter to the JA Pmod header:

```text
USB-UART adapter TX -> JA1 / Y11  -> FPGA uart_rx_i
USB-UART adapter RX -> JA2 / AA11 -> FPGA uart_tx_o
USB-UART adapter GND -> ZedBoard Pmod GND
```

Use a 3.3 V UART adapter only. Do not use 5 V UART levels. Do not connect the adapter VCC pin unless you explicitly need it for a specific adapter; the required connections are TX, RX, and common GND.

The FPGA UART RX input receives the adapter TX signal. The FPGA UART TX output drives the adapter RX signal.

## Board Setup

1. Connect the ZedBoard power adapter.
2. Connect the USB-JTAG/PROG cable to the PC for bitstream programming.
3. Connect the external 3.3 V USB-UART adapter to JA1, JA2, and Pmod GND.
4. Do not use the onboard USB-UART connector for this PL UART link; it is connected to PS MIO, not PL pins.

## Packet Format

PC request:

```text
0xA5 0x5A
command
payload_length_low
payload_length_high
payload bytes
checksum
```

`command = 0x01` means `RUN_VECTOR`.

The checksum is the 8-bit sum of command, length bytes, and payload modulo 256.

`RUN_VECTOR` payload:

```text
uint8 snr_level
int32 noise_var, little-endian, lower Q8.12 GBW_W bits used
int16 H_re[4][4], little-endian, row-major
int16 H_im[4][4], little-endian, row-major
int16 y_re[4], little-endian
int16 y_im[4], little-endian
```

Fixed-point values:

```text
H and y use Q4.12
+1.0 = 4096
-1.0 = -4096
noise_var uses Q8.12
```

Identity vector:

```text
snr_level = 2
noise_var = 0
H_re diagonal = 4096
H_re off-diagonal = 0
H_im all zero
y = [+1+j, -1+j, -1-j, +1-j]
```

FPGA response:

```text
0x5A 0xA5
status
payload_length_low
payload_length_high
payload bytes
checksum
```

Status values:

```text
0x00 OK
0x01 checksum error
0x02 bad command
0x03 bad length
0x04 busy
```

OK payload:

```text
uint8 mode
uint8 num_iters
uint8 bits[0]
uint8 bits[1]
uint8 bits[2]
uint8 bits[3]
int16 xout_re[4], little-endian
int16 xout_im[4], little-endian
```

## Simulate

From the repository root:

```powershell
C:\AMDDesignTools\2025.2.1\Vivado\bin\xtclsh.bat sim_seq\xsim_uart_mimo_protocol.tcl
C:\AMDDesignTools\2025.2.1\Vivado\bin\xtclsh.bat sim_seq\xsim_uart_mimo_detector_integration.tcl
```

The XSIM testbenches drive protocol bytes and check:

- identity QPSK vector
- bad checksum response
- bad command response
- bad length response
- busy response while the real detector is running

## Build The Bitstream

From PowerShell:

```powershell
C:\AMDDesignTools\2025.2.1\Vivado\bin\vivado.bat -mode batch -source syn_seq\vivado_impl_zedboard_uart_demo.tcl -tclargs -clock_period 20.000 -part xc7z020clg484-1
```

Outputs are written under:

```text
results/phase9_zedboard_uart/clk_20p000ns/
```

Expected bitstream:

```text
results/phase9_zedboard_uart/clk_20p000ns/zedboard_mimo_uart_top.bit
```

## Program And Connect

1. Power on the ZedBoard.
2. Connect USB-JTAG/PROG to the PC.
3. Open Vivado Hardware Manager.
4. Open target and auto-connect to the ZedBoard.
5. Program the FPGA with `zedboard_mimo_uart_top.bit`.
6. Connect the external USB-UART adapter to JA1, JA2, and GND.
7. Plug the adapter into the PC.
8. Open Windows Device Manager.
9. Expand Ports (COM & LPT).
10. Note the USB Serial Device or USB-UART adapter COM port, such as `COM5`.

Expected bitstream path:

```text
results/phase9_zedboard_uart/clk_20p000ns/zedboard_mimo_uart_top.bit
```

Optional Vivado Tcl programming outline:

```tcl
open_hw_manager
connect_hw_server
open_hw_target

puts "Available hardware devices:"
puts [get_hw_devices]

set devs [get_hw_devices xc7z020*]

if {[llength $devs] == 0} {
    error "No xc7z020 device found. Check board power, USB-JTAG cable, and Hardware Manager connection."
}

set dev [lindex $devs 0]
current_hw_device $dev
refresh_hw_device $dev

set_property PROGRAM.FILE {C:/fpga_projects/adaptive-gs-mimo-detector/results/phase9_zedboard_uart/clk_20p000ns/zedboard_mimo_uart_top.bit} $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "DONE: Programmed $dev"
```

## Run The Python Host Script

Install pyserial once:

```powershell
python -m pip install pyserial
```

Run the no-hardware packet check first:

```powershell
python python/uart_send_vector.py --dry-run
```

Send the identity vector to hardware:

```powershell
python python/uart_send_vector.py --port COM5 --baud 115200 --vector identity
```

Replace `COM5` with the COM port from Device Manager.

Expected output includes:

```text
Status: 0x00 (OK)
mode: 0
num_iters: 4
bits: 00 01 11 10
PASS: identity vector bits match expected 00 01 11 10
```

## Legacy Connection Checklist

1. Program the ZedBoard with `zedboard_mimo_uart_top.bit`.
2. Connect the external USB-UART adapter to JA1, JA2, and GND.
3. Plug the adapter into the PC.
4. Open Windows Device Manager.
5. Expand Ports (COM & LPT).
6. Note the COM port, such as `COM5`.

## LEDs

```text
LD0 heartbeat
LD1 UART RX activity
LD2 detector busy
LD3 detector done latched
LD5:LD4 mode
LD7:LD6 status/error indicator
```

## Troubleshooting

No COM port:

- Confirm the external USB-UART adapter is plugged in.
- Install the adapter driver if Windows does not recognize it.
- Use Device Manager, Ports (COM & LPT), to find the port name.

Timeout:

- Confirm the board is programmed with the UART bitstream.
- Confirm TX/RX are crossed: adapter TX to JA1, adapter RX to JA2.
- Confirm adapter GND is connected to ZedBoard GND.
- Confirm baud is `115200`.
- Confirm the adapter is 3.3 V, not 5 V.
- Confirm the board is powered and the MMCM has locked; LD0 heartbeat should blink after reset.
- Press BTNC once to reset the PL design and try again.

Checksum error:

- Re-run the Python script without editing packet bytes.
- Check for the correct baud rate and a stable ground connection.

Wrong bits:

- Confirm the Python script is using `--vector identity`.
- Run `python python/uart_send_vector.py --dry-run`.
- Re-run the XSIM protocol and integration testbenches.
- Confirm the bitstream matches the current RTL.
- Confirm the host is talking to the external USB-UART adapter COM port, not another serial port.

Board not programmed:

- Program `results/phase9_zedboard_uart/clk_20p000ns/zedboard_mimo_uart_top.bit`.
- Check Vivado Hardware Manager detects the `xc7z020`.

Reset/start issues:

- The UART packet itself starts the detector.
- Press BTNC to reset the design if the status LEDs look stuck.
- If LD0 heartbeat is not blinking, check the board clock, reset button, power, and programmed bitstream.

## Hardware Validation Result: Identity Vector PASS

Date: 2026-06-16

Milestone achieved: PC-driven UART identity-vector validation passed on physical ZedBoard hardware.

This is one successful identity-vector hardware validation. It confirms the PL UART path, packet parser, real sequential adaptive fixed-point Gauss-Seidel MIMO detector, and UART response path for this vector. It is not yet the full multi-vector hardware regression.

Bitstream used:

```text
C:/fpga_projects/adaptive-gs-mimo-detector/results/phase9_zedboard_uart/clk_20p000ns/zedboard_mimo_uart_top.bit
```

Routed checkpoint:

```text
results/phase9_zedboard_uart/clk_20p000ns/routed_zedboard_uart_demo.dcp
```

Vivado detected `arm_dap_0 xc7z020_1`; the FPGA/PL device selected and programmed was `xc7z020_1`.

The Vivado checkpoint showed no switch ports. The board-level ports were constrained as:

```text
clk       -> PIN=Y9
rst_btn   -> PIN=P16
uart_rx_i -> PIN=Y11,  LVCMOS33
uart_tx_o -> PIN=AA11, LVCMOS33
led[0:7]  -> LED pins
```

Hardware used:

- ZedBoard Zynq-7000
- Silicon Labs CP210x / CP2102 USB-to-UART bridge on `COM5`
- External 3.3 V UART through the JA Pmod connector

Physical UART wiring:

```text
CP2102 TXD -> ZedBoard JA1 / Y11  -> FPGA uart_rx_i
CP2102 RXD -> ZedBoard JA2 / AA11 -> FPGA uart_tx_o
CP2102 GND -> ZedBoard JA Pmod GND
CP2102 3V3 -> not connected
CP2102 +5V -> not connected
```

Hardware command run from the repository root:

```powershell
python python/uart_send_vector.py --port COM5 --baud 115200 --vector identity
```

Actual terminal output:

```text
Opening COM5 at 115200 baud
Request bytes: 91
Status: 0x00 (OK)
Payload length: 22
mode: 0
num_iters: 4
bits: 00 01 11 10
xout_re: [4096, -4096, -4096, 4096]
xout_im: [4096, 4096, -4096, -4096]
PASS: identity vector bits match expected 00 01 11 10
```

Interpretation:

- The PC sent a 91-byte UART `RUN_VECTOR` request to the FPGA.
- The FPGA accepted the packet, ran the real sequential detector, selected mode `0` / GS-4, and completed `4` iterations.
- Returned bits were `00 01 11 10`, matching the expected identity-vector QPSK decisions.
- In Q4.12 fixed-point, `+1.0 = 4096` and `-1.0 = -4096`.
- The returned `xout` values correspond to `+1 + j`, `-1 + j`, `-1 - j`, and `+1 - j`.

Expected QPSK bit mapping:

```text
+re +im -> 00
-re +im -> 01
-re -im -> 11
+re -im -> 10
```

Evidence checklist:

- PowerShell PASS screenshot
- Board photo/video with LD0 heartbeat
- CP2102-to-JA wiring photo
- Vivado programming log showing `xc7z020_1` selected
- Vivado post-route reports under `results/phase9_zedboard_uart/clk_20p000ns/`

Conclusion: the physical UART identity-vector hardware validation passed.

Next step: extend the UART host flow to run a multi-vector hardware regression covering GS-4, GS-8, GS-16, non-diagonal channels, complex channels, nonzero `noise_var`, and adaptive boundary cases.

## Multi-Vector UART Regression

The controlled batch regression script is:

```powershell
python python/uart_batch_regression.py --dry-run --vector-set basic
```

The hardware command is:

```powershell
python python/uart_batch_regression.py --port COM5 --baud 115200 --vector-set basic
```

To run only the already hardware-validated identity vector:

```powershell
python python/uart_batch_regression.py --port COM5 --baud 115200 --vector-set basic --limit 1
```

The initial `basic` vector set begins with `identity_gs4`, the physical ZedBoard PASS case documented above. It also loads a small deterministic set from `vectors/phase6_rtl_vectors/phase6_vectors_summary.json` to start covering real non-diagonal `H`, complex `H`, nonzero `noise_var`, GS-4, GS-8, and GS-16 cases.

This script does not change the UART packet format or FPGA design. It reuses the existing UART frame construction, checksum, serial readback, and response decoder helpers from `python/uart_send_vector.py`.

### Basic Batch Hardware Result: PASS

Date: 2026-06-16

Saved hardware log:

```text
results/phase9_zedboard_uart/clk_20p000ns/uart_batch_basic_hw_log.txt
```

Command used to capture the saved log:

```powershell
python python\uart_batch_regression.py --port COM5 --baud 115200 --vector-set basic --timeout 10 *>&1 | Tee-Object -FilePath results\phase9_zedboard_uart\clk_20p000ns\uart_batch_basic_hw_log.txt
```

The `basic` hardware batch passed on `COM5` at `115200` baud with four vectors:

```text
identity_gs4                 PASS  mode 0 / GS-4   num_iters 4
phase6_real_nondiagonal_gs4  PASS  mode 0 / GS-4   num_iters 4
phase6_complex_noise_gs8     PASS  mode 1 / GS-8   num_iters 8
phase6_complex_noise_gs16    PASS  mode 2 / GS-16  num_iters 16
```

Terminal summary:

```text
Total: 4/4 PASS
Mode coverage:
GS-4: 2
GS-8: 1
GS-16: 1
```

This confirms that the physical ZedBoard UART path can run the current deterministic `basic` vector set through the real sequential detector and return exact expected mode, iteration count, detected bits, and `xout` values. This result covers the current four-vector `basic` set only; it is not yet an exhaustive hardware regression across all generated vectors or corner cases.

## Extended UART Hardware Regression

For the consolidated physical hardware pass/fail record, including the completed 20-vector and 50-vector UART regression results, see `docs/uart_hardware_regression_results.md`.

The batch runner supports these deterministic vector sets:

- `basic`: 4 deterministic vectors. This set has passed on physical ZedBoard hardware.
- `phase6_20`: target 20-vector deterministic set for stronger hardware regression.
- `phase6_50`: target 50-vector deterministic set for broader hardware regression.

The extended sets keep the `basic` vectors first, then select additional golden vectors generated by the Phase 6 fixed-point Python model. `phase6_20` uses `vectors/phase6_rtl_vectors/phase6_vectors_summary.json`. `phase6_50` uses `vectors/phase6_rtl_vectors/phase6_uart_50_vectors_summary.json`, which is generated with:

```powershell
python python/export_phase6_rtl_vectors.py --profile uart --num-vectors 50 --json-output vectors/phase6_rtl_vectors/phase6_uart_50_vectors_summary.json --skip-sv
```

The earlier `phase6_50` attempt selected only 20 vectors because only 20 deterministic vectors were available in the original JSON summary. The new JSON-only UART export flow preserves the existing 20 generated Phase 6 vectors, appends 30 deterministic fixed-point golden vectors, and enables a true 50-vector dry-run and hardware regression without rewriting the SystemVerilog vector package.

Dry-run commands:

```powershell
python python/uart_batch_regression.py --dry-run --vector-set basic
python python/uart_batch_regression.py --dry-run --vector-set phase6_20
python python/uart_batch_regression.py --dry-run --vector-set phase6_50
```

Hardware commands:

```powershell
python python/uart_batch_regression.py --port COM5 --baud 115200 --vector-set phase6_20 --timeout 10
python python/uart_batch_regression.py --port COM5 --baud 115200 --vector-set phase6_50 --timeout 10
```

Suggested log-capture commands:

```powershell
python python\uart_batch_regression.py --port COM5 --baud 115200 --vector-set phase6_20 --timeout 10 *>&1 | Tee-Object -FilePath results\phase9_zedboard_uart\clk_20p000ns\uart_batch_phase6_20_hw_log.txt
python python\uart_batch_regression.py --port COM5 --baud 115200 --vector-set phase6_50 --timeout 10 *>&1 | Tee-Object -FilePath results\phase9_zedboard_uart\clk_20p000ns\uart_batch_phase6_50_hw_log.txt
```

### Phase6 20-Vector Hardware Result: PASS

The `phase6_20` hardware regression passed on physical ZedBoard hardware with:

```powershell
python python\uart_batch_regression.py --port COM5 --baud 115200 --vector-set phase6_20 --timeout 10
```

Result:

```text
Total: 20/20 PASS
Mode coverage:
GS-4: 3
GS-8: 2
GS-16: 15
Vector source coverage:
identity: 1
phase6 JSON: 19
```

For all 20 vectors, mode, `num_iters`, bits, `xout_re`, and `xout_im` matched exactly.

### Phase6 50-Vector Status

The `phase6_50` dry-run now selects 50 deterministic vectors. The generated set currently has this mode distribution:

```text
GS-4: 17
GS-8: 17
GS-16: 16
```

The 50-vector hardware result should only be claimed after running the `phase6_50` hardware command and seeing every vector report PASS with the final `Total: 50/50 PASS` summary.
