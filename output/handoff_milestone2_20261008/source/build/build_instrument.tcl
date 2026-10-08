# Build-only script for the first playable instrument milestone.
# Run with Gowin gw_sh.exe; this script never programs hardware.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set build_gao 0
if {[info exists ::env(FPGA_BUILD_GAO)]} {
    set build_gao $::env(FPGA_BUILD_GAO)
}
if {$build_gao eq "1"} {
    set build_dir [file join $root build gowin_single_voice_gao]
} else {
    set build_dir [file join $root build gowin_single_voice]
}
set project_dir [file join $build_dir instrument]
set gprj_file [file join $project_dir instrument instrument.gprj]
set wave_dir [file join $root rtl audio]
set wave_hex [file join $wave_dir wave_sine.hex]
set gao_config [file join $root rtl gao_top.rao]

if {![file exists $wave_hex]} {
    error "Wavetable initialization file not found: $wave_hex"
}

file mkdir $project_dir

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

# Gowin resolves $readmemh relative to this include path during both Tcl and
# IDE-driven synthesis. The same directory contains the one-cycle sine table.
set_option -top_module top
set_option -output_base_name instrument
set_option -include_path $wave_dir

# Keep normal and GAO builds in separate projects so the normal bitstream
# remains reproducible. GAO is opt-in through build.ps1 -Gao.
if {$build_gao eq "1"} {
    if {![file exists $gao_config]} {
        error "GAO configuration not found: $gao_config"
    }
    set fh [open $gprj_file r]
    set gprj_text [read $fh]
    close $fh
    if {[string first "gao_top.rao" $gprj_text] < 0} {
        add_file $gao_config
    }
}

cd $root
run all
