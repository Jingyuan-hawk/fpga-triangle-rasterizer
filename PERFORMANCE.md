# Frame Draw Performance

The Arty A7-100T draws the same 320x240 scene of three triangles in both versions. A 32-bit hardware counter starts with the first clear command after reset and latches when the third triangle completes. The count excludes UART frame transmission and the power-on reset delay. XSIM reads the count from the UART frame header. At 100 MHz, one cycle is 10 ns and time in milliseconds is cycles / 100000.

| Version | Frame cycles | Frame time | Triangle phase cycles | Post-route setup WNS |
| --- | ---: | ---: | ---: | ---: |
| One lane with counter | 186253 | 1.86253 ms | 109451 | +0.290 ns |
| Four lanes with counter | 104444 | 1.04444 ms | 27642 | +0.158 ns |

The clear and control phase takes 76802 cycles in both versions. Four lanes save 81809 cycles, or 0.81809 ms, for the complete frame: 1.783 times faster and 43.92% fewer cycles. The triangle phase alone is 3.960 times faster. The setup times above are from Vivado 2025.2 routed implementations for xc7a100tcsg324-1.

| Version | Slice LUTs | Slice registers | Block RAM tiles | DSPs |
| --- | ---: | ---: | ---: | ---: |
| One lane | 1352 | 847 | 9 | 9 |
| Four lanes | 2151 | 941 | 12 | 12 |

The single-lane measurement is commit `80592b7`. The four-lane measurement is the current version. XSIM passes shared-edge, clipping, winding, fractional-coordinate, and four-bank boundary cases. The full 320x240 framebuffer matches an independent edge-function reference pixel by pixel. The Arty top simulation checks the UART cycle count and first pixel. The timing numbers come from simulation and routed timing analysis; the boards have not been measured physically here.
