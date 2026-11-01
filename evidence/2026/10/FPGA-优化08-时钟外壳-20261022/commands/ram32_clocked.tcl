# Dual-clock 32-voice prototype PnR: 12.288 MHz reference + 73.728 MHz compute.
# Standalone prototype entry, not a product profile.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
if {[info exists ::env(FPGA_BUILD_RUN_DIR)]} {
    set run_dir [file normalize $::env(FPGA_BUILD_RUN_DIR)]
} else {
    set run_dir [file normalize [file join $root .. .. tmp ram32_clocked_run]]
}
file mkdir $run_dir
create_project -name ram32c -dir $run_dir -pn GW2A-LV18PG256C8/I7 -device_version C

set sources {
    rtl/prototypes/ram32_clocked_wrap.v
    rtl/prototypes/ram32_clocked_top.v
    rtl/prototypes/voice_sched32.v
    rtl/prototypes/instrument_rom_banks.v
    rtl/prototypes/instrument_ram_audio_compute.v
    rtl/prototypes/instrument_ram_wavetable_engine.v
    rtl/audio/audio_pll_clock.v
    rtl/audio/audio_frame_bridge_stereo.v
    rtl/audio/voice_state_ram.v
    rtl/audio/note_phase_inc.v
    rtl/audio/wide_master.v
    rtl/audio/i2s_tx.v
    rtl/audio/split_audio_multiplier.v
    rtl/audio/gowin_prom_wave_sine.v
    rtl/audio/gowin_prom_piano_bank.v
    rtl/audio/gowin_prom_guitar_bank.v
    rtl/audio/gowin_prom_bright_bank.v
}
foreach src $sources { add_file [file join $root $src] }
add_file [file join $root constraints ram32_clocked.sdc]
set_option -top_module ram32_clocked_wrap
set_option -output_base_name ram32c

set project_work [file join $run_dir ram32c]
file mkdir [file join $project_work rtl audio]
foreach header [glob -directory [file join $root rtl audio] *.vh] {
    file copy -force $header [file join $project_work rtl audio [file tail $header]]
}
cd $project_work
run all
