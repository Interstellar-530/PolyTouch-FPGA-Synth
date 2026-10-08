# Build-only script for the first playable instrument milestone.
# Run with Gowin gw_sh.exe; this script never programs hardware.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set build_dir [file join $root build gowin_single_voice]
set project_dir [file join $build_dir instrument]
file mkdir $project_dir
set gprj_file [file join $project_dir instrument instrument.gprj]

if {![file exists $gprj_file]} {
    create_project -name instrument -dir $project_dir -pn GW2A-LV18PG256C8/I7 -device_version C
    add_file [file join $root rtl top.v]
    add_file [file join $root rtl audio dds_osc.v]
    add_file [file join $root rtl audio adsr.v]
    add_file [file join $root rtl audio voice.v]
    add_file [file join $root rtl audio pt8211_tx.v]
    add_file [file join $root constraints primer20k_dock3714.cst]
    add_file [file join $root constraints primer20k.sdc]
} else {
    open_project $gprj_file -pn GW2A-LV18PG256C8/I7 -device_version C
}

set_option -top_module top
set_option -output_base_name instrument
cd $root
run all
