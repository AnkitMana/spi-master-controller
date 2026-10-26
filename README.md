# SPI Master Controller

A parameterized SPI master designed in Verilog, verified using SystemVerilog, and implemented in AMD Vivado.

## Features
- Supports all four SPI modes (CPOL/CPHA)
- Serial data transmission and reception
- Configurable clock divider
- TX-ready and RX-data-valid status signals
- Synchronous reset recovery, including mid-transfer reset testing

## Verification
A self-checking SystemVerilog testbench verifies SPI transfers across all four modes using multiple data patterns, alongside status-signal and reset checks.

- **Testbench checks passed:** 456/456
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

*Timing results depend on the applied timing constraints.*

## Tools
- Verilog HDL
- SystemVerilog
- AMD Vivado
- Static Timing Analysis (STA)

## Repository Structure

```text
spi-master-controller/
├── README.md
├── rtl/
│   └── SPI_master.v
└── testbench/
    └── SPI_Master_TB.sv
```

## Skills Demonstrated
RTL design, SPI protocol implementation, self-checking verification, FPGA implementation, resource utilization analysis, and introductory static timing analysis.
