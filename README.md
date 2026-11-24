# FPGA Triangle Rasterizer

This version rasterizes triangles defined by vertex coordinates and RGB565 colors on an Arty A7-100T. It uses one pixel lane and the board's 100 MHz clock.

The rasterizer has six states: IDLE latches the three vertices and color; CALC_AREA latches the signed area; ORIENT latches the vertices in counterclockwise order; BBOX latches the clipped bounds and first sample position; INIT_EDGE latches the initial edge values; RUN tests one pixel on each clock when the write port is ready. CALC_AREA and INIT_EDGE each take two clocks so multiplication and subtraction are separated. The clocked block only resets or copies the next register values.

Vivado 2025.2 post-route setup timing on the Arty A7-100T has WNS +0.126 ns at 100 MHz in the clean pipeline project. The earlier unpipelined version had WNS -21.695 ns. XSIM passes the pixel coverage and Arty UART tests, including changed input buses after triangle acceptance and a triangle completely outside the frame.

Run `sim/run_xsim.ps1` for simulation. Run `vivado/create_project.tcl` and then `vivado/build_bitstream.tcl` in Vivado batch mode to build the board image. Open `build/vivado_pipeline_100/arty_rasterizer_pipeline_100.xpr` in the GUI. The build script publishes `arty_a7_rasterizer.bit` only when setup timing passes.
