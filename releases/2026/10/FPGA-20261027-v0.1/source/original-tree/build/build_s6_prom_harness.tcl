# Build-only script: synthesise the pROM variant to confirm the explicit primitive.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set build_dir [file join $root build gowin_s6_prom_harness]
set project_dir [file join $build_dir prom]
file mkdir $project_dir
set gprj_file [file join $project_dir prom prom.gprj]
if {![file exists $gprj_file]} {
    create_project -name prom -dir $project_dir -pn GW2A-LV18PG256C8/I7 -device_version C
    add_file [file join $root rtl synth_s6_prom_harness.v]
    add_file [file join $root rtl audio wavetable_osc_dual_prom.v]
    add_file [file join $root rtl audio gowin_prom_wave_sine.v]
    add_file [file join $root rtl audio gowin_prom_wave_bright.v]
    add_file [file join $root constraints primer20k_s6_prom_harness.cst]
    add_file [file join $root constraints primer20k.sdc]
} else {
    open_project $gprj_file -pn GW2A-LV18PG256C8/I7 -device_version C
}
set_option -top_module synth_s6_prom_harness
set_option -output_base_name prom
cd $root
run all