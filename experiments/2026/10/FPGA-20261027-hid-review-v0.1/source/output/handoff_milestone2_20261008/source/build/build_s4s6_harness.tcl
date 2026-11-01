# Build-only script for the S4-S6 synthesis/PnR measurement harness.
# Run with Gowin gw_sh.exe; this script never programs hardware.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set build_dir [file join $root build gowin_s4s6_harness]
set project_dir [file join $build_dir harness]
file mkdir $project_dir
set gprj_file [file join $project_dir harness harness.gprj]

if {![file exists $gprj_file]} {
    create_project -name harness -dir $project_dir -pn GW2A-LV18PG256C8/I7 -device_version C
    add_file [file join $root rtl synth_s4s6_harness.v]
    add_file [file join $root rtl audio mcp3208_spi.v]
    add_file [file join $root rtl audio pressure_bend.v]
    add_file [file join $root rtl audio wavetable_rom_dual.v]
    add_file [file join $root rtl audio wavetable_osc_dual_s6.v]
    add_file [file join $root rtl audio mixer_s6.v]
    add_file [file join $root constraints primer20k_s4s6_harness.cst]
    add_file [file join $root constraints primer20k.sdc]
} else {
    open_project $gprj_file -pn GW2A-LV18PG256C8/I7 -device_version C
}

set_option -top_module synth_s4s6_harness
set_option -output_base_name harness
cd $root
run all
