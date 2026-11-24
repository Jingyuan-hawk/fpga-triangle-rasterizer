# FPGA Triangle Rasterizer

This version rasterizes triangles defined by specified vertex coordinates and RGB565 colors on an Arty A7-100T. It uses one pixel lane and the board's 100 MHz clock.

The unpipelined design has a severe setup violation from `tri_index_reg[1]_replica` to `row1_reg[62]` (slack: -21.436 ns). The worst reported setup path ends at `e1_reg[61]` with slack of -21.695 ns. The design passes functional simulation but does not meet 100 MHz hardware timing.
