set root [file normalize [file dirname [info script]]]
set build_dir [file join $root build]
file mkdir $build_dir
create_project -name ddr3_smoke -dir $build_dir -pn GW2A-LV18PG256C8/I7 -device_version C
add_file [file join $root src ddr3_memory_interface ddr3_memory_interface.v]
add_file [file join $root src gowin_rpll gowin_rpll.v]
add_file [file join $root src ddr3_smoke_top.v]
add_file [file join $root src tester.v]
add_file [file join $root src uart_tx_V2.v]
add_file [file join $root src ddr3.cst]
add_file [file join $root src ddr3.sdc]
set_option -top_module ddr3_smoke_top
set_option -output_base_name ddr3_smoke
cd [file join $root src]
run all