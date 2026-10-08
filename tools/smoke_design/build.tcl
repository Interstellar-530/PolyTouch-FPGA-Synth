# Build-only diagnostic. Never programs hardware.
set source_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $source_dir ../..]]
set build_dir [file join $root tmp gowin_smoke]
file mkdir $build_dir
if {![file exists [file join $build_dir mcp_smoke.gprj]]} {
    create_project -name mcp_smoke -dir $build_dir -pn GW2A-LV18PG256C8/I7 -device_version C
    add_file [file join $source_dir top.v]
    add_file [file join $source_dir pins.cst]
    add_file [file join $source_dir timing.sdc]
} else {
    open_project [file join $build_dir mcp_smoke.gprj] -pn GW2A-LV18PG256C8/I7 -device_version C
}
set_option -top_module top
set_option -output_base_name mcp_smoke
run all
