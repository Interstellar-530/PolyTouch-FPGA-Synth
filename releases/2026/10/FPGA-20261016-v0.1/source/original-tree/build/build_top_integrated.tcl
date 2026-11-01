# Build-only script for the integrated top (S2 GPIO keyboard + S4/S5 ADC path +
# S6 dual-wavetable voices and mixer_s6 + S3 i2s_tx file kept in the project).
# Run with Gowin gw_sh.exe; this script never programs hardware.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set build_dir [file join $root build gowin_top_integrated]
set project_dir [file join $build_dir instrument]
file mkdir $project_dir
set gprj_file [file join $project_dir instrument instrument.gprj]

if {![file exists $gprj_file]} {
    create_project -name instrument -dir $project_dir -pn GW2A-LV18PG256C8/I7 -device_version C
    # 顶层用调试档封装（build/isolated/top_dbg_build.v），把标准 I2S 的四根输出收进内部，
    # 避免未约束端口被自动放到 SOM 互连脚上。生产 RTL rtl/top.v 仍是被实例化的模块。
    add_file [file join $root build isolated top_dbg_build.v]
    add_file [file join $root rtl top.v]
    add_file [file join $root rtl audio dds_osc.v]
    add_file [file join $root rtl audio adsr.v]
    add_file [file join $root rtl audio poly_voice.v]
    add_file [file join $root rtl audio poly_voice_s6.v]
    add_file [file join $root rtl audio note_phase_inc.v]
    add_file [file join $root rtl audio event_fifo.v]
    add_file [file join $root rtl audio voice_alloc.v]
    add_file [file join $root rtl audio song_player.v]
    add_file [file join $root rtl audio mixer_s6.v]
    add_file [file join $root rtl audio pt8211_tx.v]
    # i2s_tx 在 AUDIO_IF=1 的 generate 分支里实例化；本档不展开但仍加入文件表，
    # 避免综合器对未定义模块的保守报错。标准档见 build/build_top_i2s_std.tcl。
    add_file [file join $root rtl audio i2s_tx.v]
    add_file [file join $root rtl audio uart_ctrl.v]
    add_file [file join $root rtl audio gpio_keyboard.v]
    add_file [file join $root rtl audio mcp3208_spi.v]
    add_file [file join $root rtl audio pressure_bend.v]
    add_file [file join $root rtl audio shared_wavetable_engine.v]
    add_file [file join $root rtl audio global_crossfade.v]
    add_file [file join $root rtl audio gowin_prom_wave_sine.v]
    add_file [file join $root rtl audio gowin_prom_wave_bright.v]
    add_file [file join $root rtl audio wavetable_rom_dual.v]
    add_file [file join $root rtl audio wavetable_osc_dual_s6.v]
    add_file [file join $root constraints primer20k_dock3714.cst]
    add_file [file join $root constraints primer20k.sdc]
} else {
    open_project $gprj_file -pn GW2A-LV18PG256C8/I7 -device_version C
}

set_option -top_module top_dbg_build
set_option -output_base_name instrument
cd $root
run all
