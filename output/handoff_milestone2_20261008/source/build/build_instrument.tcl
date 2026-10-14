# Build-only script for the four-voice polyphonic instrument.
# Run with Gowin gw_sh.exe; this script never programs hardware.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set build_dir [file join $root build gowin_poly]
set project_dir [file join $build_dir instrument]
file mkdir $project_dir
set gprj_file [file join $project_dir instrument instrument.gprj]
set gpio_file [file join $root rtl audio gpio_keyboard.v]

if {![file exists $gprj_file]} {
    create_project -name instrument -dir $project_dir -pn GW2A-LV18PG256C8/I7 -device_version C
    add_file [file join $root rtl top.v]
    add_file [file join $root rtl audio dds_osc.v]
    add_file [file join $root rtl audio adsr.v]
    add_file [file join $root rtl audio poly_voice.v]
    add_file [file join $root rtl audio note_phase_inc.v]
    add_file [file join $root rtl audio event_fifo.v]
    add_file [file join $root rtl audio voice_alloc.v]
    add_file [file join $root rtl audio song_player.v]
    add_file [file join $root rtl audio mixer.v]
    add_file [file join $root rtl audio pt8211_tx.v]
    add_file [file join $root rtl audio uart_ctrl.v]
    add_file $gpio_file
    add_file [file join $root constraints primer20k_dock3714.cst]
    add_file [file join $root constraints primer20k.sdc]
} else {
    open_project $gprj_file -pn GW2A-LV18PG256C8/I7 -device_version C
    # 旧的本地工程创建于 S2 前，打开后补入新模块。重复构建不重复添加。
    set project_text [read [set project_handle [open $gprj_file r]]]
    close $project_handle
    if {[string first "gpio_keyboard.v" $project_text] < 0} {
        add_file $gpio_file
    }
}

set_option -top_module top
set_option -output_base_name instrument
cd $root
run all
