# FPGA Triangle Rasterizer

This version draws three RGB565 triangles on a 320x240 framebuffer using the Arty A7-100T 100 MHz clock. The triangle setup is shared, and the RUN state tests four adjacent pixels per clock. Four framebuffer banks accept the resulting writes. The original single-lane rasterizer remains in `rtl/rasterizer1.sv` for comparison.

The board counts clock cycles from the first clear command through completion of the third triangle. The count is sent as a little-endian 32-bit value after the RAST magic and frame dimensions, before the RGB565 pixels. `host/capture_frame.ps1` prints the cycles and milliseconds while saving the image.

In XSIM, the single-lane reference took 186253 cycles (1.86253 ms) and the four-lane version took 104444 cycles (1.04444 ms), including the same 76802-cycle clear and control phase. The four-lane result is 1.783 times faster for the full frame. See `PERFORMANCE.md` for the timing definition, triangle-only comparison, utilization, and verification results.

Run `sim/run_xsim.ps1` for simulation. Run `vivado/create_project.tcl` and then `vivado/build_bitstream.tcl` in Vivado batch mode to build the board image. Open `build/vivado_four_lane_100/arty_rasterizer_four_lane_100.xpr` in the GUI. The build script publishes `arty_a7_rasterizer.bit` only when 100 MHz setup timing passes.
