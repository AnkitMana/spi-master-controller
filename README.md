# SPI Master Controller

A parameterized SPI master controller implemented in Verilog and verified using a self-checking SystemVerilog testbench in AMD Vivado.

## Features
- Supports all four SPI modes (CPOL/CPHA: 00, 01, 10, 11)
- Serial data transmission and reception
- Configurable clock divider
- Ready and receive-data-valid status signals
- Reset and mid-transfer reset recovery

## Verification
The self-checking testbench exercises all four SPI modes using multiple TX/RX data patterns and checks clock polarity, transmitted and received data, status signals, and reset recovery.

- **Checks passed:** 456/456
- **Failed checks:** 0

## FPGA Implementation

| Metric | Result |
|---|---:|
| Target device | Xilinx Zynq-7000 (`xc7z020clg400`) |
| LUTs | 24 |
| Slice registers | 38 |
| Worst Negative Slack (WNS) | +7.291 ns |
| Worst Hold Slack (WHS) | +0.201 ns |
| Total Negative Slack (TNS) | 0 ns |

Timing results depend on the constraints used for implementation.

## Tools
- Verilog HDL
- SystemVerilog
- AMD Vivado

## Project Structure
- `SPI_master.v` — SPI master RTL
- `SPI_Master_TB.sv` — self-checking simulation testbench

## Scope
This project demonstrates RTL design, simulation-based verification, FPGA implementation, and introductory static timing analysis.
