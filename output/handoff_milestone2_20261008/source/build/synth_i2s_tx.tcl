# [S3-AI | deepseek | 2026-10-14] i2s_tx 隔离综合脚本（Gowin gw_sh）。
#
# 两个变体：标准档 12.288 MHz / 48 kHz，DATA_BITS = 16 与 24。
# 工程与报告生成在工作区 tmp/gowin_i2s_tx/ 下，不改生产工程、不烧录。
# 引脚分配只服务于本隔离工程：clk=T7、i2s_bck=B12、i2s_lrck=C12、i2s_din=B13，
# 取自 docs/hardware/FPGA-pinplan-20261013-v0.1.csv 的候选表，不写入生产 CST。
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set repo [file normalize [file join $root .. .. ..]]
set out_root [file join $repo tmp gowin_i2s_tx]
file mkdir $out_root

set wrapper [file join $script_dir isolated i2s_tx_top.v]
set rtl_file [file join $root rtl audio i2s_tx.v]

proc build_variant {name data_bits} {
    global out_root wrapper rtl_file
    set project_dir [file join $out_root $name]
    file mkdir $project_dir
    set gprj [file join $project_dir i2s_tx $name.gprj]
    create_project -name $name -dir $project_dir -pn GW2A-LV18PG256C8/I7 -device_version C
    add_file $wrapper
    add_file $rtl_file
    set cst [file join $project_dir ${name}.cst]
    set sdc [file join $project_dir ${name}.sdc]
    set fh [open $cst w]
    puts $fh "IO_LOC \"clk\" T7;"
    puts $fh "IO_PORT \"clk\" IO_TYPE=LVCMOS33;"
    puts $fh "IO_LOC \"i2s_bck\" B12;"
    puts $fh "IO_PORT \"i2s_bck\" IO_TYPE=LVCMOS33 DRIVE=8;"
    puts $fh "IO_LOC \"i2s_lrck\" C12;"
    puts $fh "IO_PORT \"i2s_lrck\" IO_TYPE=LVCMOS33 DRIVE=8;"
    puts $fh "IO_LOC \"i2s_din\" B13;"
    puts $fh "IO_PORT \"i2s_din\" IO_TYPE=LVCMOS33 DRIVE=8;"
    close $fh
    set fh [open $sdc w]
    puts $fh "create_clock -name clk -period 81.38 \[get_ports {clk}\]"
    close $fh
    add_file $cst
    add_file $sdc
    set_option -top_module i2s_tx_top
    set_option -output_base_name $name
    run all
}

build_variant i2s_tx_std16 16
build_variant i2s_tx_std24 24
