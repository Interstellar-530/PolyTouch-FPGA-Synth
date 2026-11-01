# Build-only script: resource comparison of the per-voice and shared voice engines.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]

proc build_variant {root name top extra_files} {
    set build_dir [file join $root build "gowin_$name"]
    set project_dir [file join $build_dir $name]
    file mkdir $project_dir
    set gprj_file [file join $project_dir $name "$name.gprj"]
    if {![file exists $gprj_file]} {
        create_project -name $name -dir $project_dir -pn GW2A-LV18PG256C8/I7 -device_version C
        add_file [file join $root rtl "$top.v"]
        foreach f $extra_files { add_file $f }
        add_file [file join $root constraints primer20k_s6_prom_harness.cst]
        add_file [file join $root constraints primer20k.sdc]
    } else {
        open_project $gprj_file -pn GW2A-LV18PG256C8/I7 -device_version C
    }
    set_option -top_module $top
    set_option -output_base_name $name
    cd $root
    run all
}

build_variant $root per_voice synth_voices_per_voice_harness [list \
    [file join $root rtl audio wavetable_osc_dual_prom.v] \
    [file join $root rtl audio gowin_prom_wave_sine.v] \
    [file join $root rtl audio gowin_prom_wave_bright.v] \
    [file join $root rtl audio mixer_s6.v]]
build_variant $root shared synth_voices_shared_harness [list \
    [file join $root rtl audio shared_wavetable_engine.v] \
    [file join $root rtl audio global_crossfade.v] \
    [file join $root rtl audio gowin_prom_wave_sine.v] \
    [file join $root rtl audio gowin_prom_wave_bright.v]]