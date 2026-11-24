set project_root [file normalize [file join [file dirname [info script]] ..]]
set project_dir [file join $project_root build vivado_100]
file mkdir $project_dir
create_project arty_rasterizer_100 $project_dir -part xc7a100tcsg324-1 -force

add_files -norecurse [list \
    [file join $project_root rtl rasterizer1.sv] \
    [file join $project_root rtl framebuffer_rgb565.sv] \
    [file join $project_root rtl raster_top.sv] \
    [file join $project_root board uart_tx.sv] \
    [file join $project_root board arty_a7_top.sv] \
]
add_files -fileset constrs_1 -norecurse \
    [file join $project_root board arty_a7_100.xdc]
set_property top arty_a7_top [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "Created Arty A7-100T project at $project_dir"
