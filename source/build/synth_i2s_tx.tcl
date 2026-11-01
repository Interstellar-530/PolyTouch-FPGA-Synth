# [S3-AI | deepseek | 2026-10-14] i2s_tx 隔离综合脚本（Gowin gw_sh）。
# [S3-REVIEW | Codex | 2026-10-14] 各变体生成明确位宽的包装源，禁止两次都用默认16位。
#
# 两个变体：标准档 12.288 MHz / 48 kHz，DATA_BITS = 16 与 24。
# 工程与报告生成在工作区 tmp/gowin_i2s_tx/ 下，不改生产工程、不烧录。
# 引脚分配只服务于本隔离工程：clk=T7、i2s_bck=B12、i2s_lrck=C12、i2s_din=B13，
# 取自 docs/hardware/FPGA-pinplan-20261013-v0.1.csv 的候选表，不写入生产 CST。
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set repo [file normalize [file join $root .. .. ..]]
set out_root [file join $repo tmp gowin_i2s_tx]
if {[info exists env(FPGA_I2S_SYNTH_OUT_DIR)]} {
    set out_root [file normalize $env(FPGA_I2S_SYNTH_OUT_DIR)]
}
file mkdir $out_root
cd $root
puts "S3_SYNTH_OUTPUT: $out_root"

set wrapper [file join $script_dir isolated i2s_tx_top.v]
set rtl_file [file join $root rtl audio i2s_tx.v]

proc build_variant {name data_bits} {
    global out_root wrapper rtl_file root
    set project_dir [file join $out_root $name]
    file mkdir $project_dir
    set fh [open $wrapper r]
    set wrapper_source [read $fh]
    close $fh
    if {[regsub {parameter integer DATA_BITS[ \t]+=[ \t]+16} $wrapper_source \
         "parameter integer DATA_BITS = $data_bits" variant_source] != 1} {
        error "S3_SYNTH_CONFIG: DATA_BITS template not found"
    }
    set variant_wrapper [file join $project_dir ${name}_top.v]
    set fh [open $variant_wrapper w]
    puts $fh $variant_source
    close $fh
    puts "S3_SYNTH_CONFIG: $name DATA_BITS=$data_bits wrapper=$variant_wrapper"
    set gprj [file join $project_dir i2s_tx $name.gprj]
    create_project -name $name -dir $project_dir -pn GW2A-LV18PG256C8/I7 -device_version C
    add_file $variant_wrapper
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
    # 编译相对包含路径，同时让所有构建输出留在临时隔离工程内。
    # 临时副本直接来自唯一参数头，不维护另一份生产参数。
    set include_copy [file join [pwd] rtl audio clk_params.vh]
    file mkdir [file dirname $include_copy]
    file copy -force [file join $root rtl audio clk_params.vh] $include_copy
    run all
}

if {[catch {
    build_variant i2s_tx_std16 16
    build_variant i2s_tx_std24 24
} build_error]} {
    puts stderr "S3_SYNTH_FAILED: $build_error"
    exit 1
}
exit 0
