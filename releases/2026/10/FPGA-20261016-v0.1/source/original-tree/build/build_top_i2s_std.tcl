# [集成] 标准 I2S 档（AUDIO_IF=1）综合 + 布局布线脚本，用 Gowin gw_sh 运行。
# 与 build_top_integrated.tcl（调试档）成对：两档共用同一份 rtl/top.v，各自用
# build/isolated/ 下的薄封装把本档需要的端口引到芯片边界，点流互斥、不能同时接。
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set build_dir [file join $root build gowin_top_i2s_std]
set project_dir [file join $build_dir instrument]
file mkdir $project_dir
set gprj_file [file join $project_dir instrument instrument.gprj]

if {![file exists $gprj_file]} {
    create_project -name instrument -dir $project_dir -pn GW2A-LV18PG256C8/I7 -device_version C
    add_file [file join $root build isolated top_std_build.v]
    add_file [file join $root rtl top.v]
    foreach src {
        rtl/audio/dds_osc.v rtl/audio/adsr.v rtl/audio/poly_voice.v
        rtl/audio/poly_voice_s6.v rtl/audio/wavetable_osc_dual_s6.v
        rtl/audio/note_phase_inc.v rtl/audio/event_fifo.v rtl/audio/voice_alloc.v
        rtl/audio/song_player.v rtl/audio/mixer_s6.v rtl/audio/pt8211_tx.v
        rtl/audio/i2s_tx.v rtl/audio/uart_ctrl.v rtl/audio/gpio_keyboard.v
        rtl/audio/mcp3208_spi.v rtl/audio/pressure_bend.v
        rtl/audio/shared_wavetable_engine.v rtl/audio/global_crossfade.v
        rtl/audio/gowin_prom_wave_sine.v rtl/audio/gowin_prom_wave_bright.v
        rtl/audio/wavetable_rom_dual.v rtl/audio/clk_params.vh
    } {
        add_file [file join $root $src]
    }
    add_file [file join $root constraints primer20k_i2s.cst]
    add_file [file join $root constraints primer20k_i2s.sdc]
} else {
    open_project $gprj_file -pn GW2A-LV18PG256C8/I7 -device_version C
}

set_option -top_module top_std_build
set_option -output_base_name instrument
cd $root
run all