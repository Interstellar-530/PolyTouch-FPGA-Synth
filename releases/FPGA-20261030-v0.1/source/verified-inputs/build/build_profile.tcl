# Shared source/profile manifest; always create a new project so old GPRJ files
# cannot retain an incomplete source list. Relative ROM initialization uses root.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set handle [open [file join $script_dir profiles.tsv] r]
set rows [split [string trim [read $handle]] \n]
close $handle
set selected {}
foreach row $rows {
    set columns [split [string trim $row] \t]
    if {[lindex $columns 0] eq $profile} { set selected $columns }
}
if {[llength $selected] != 5} { error "Unknown build profile: $profile" }
lassign $selected profile directory top_module cst sdc
if {[info exists ::env(FPGA_BUILD_RUN_DIR)]} {
    set run_dir [file normalize $::env(FPGA_BUILD_RUN_DIR)]
} else {
    set run_dir [file join $script_dir $directory runs [clock clicks]]
}
file mkdir $run_dir
create_project -name instrument -dir $run_dir -pn GW2A-LV18PG256C8/I7 -device_version C
set wrapper [file join $script_dir isolated ${top_module}.v]
if {[info exists ::env(FPGA_BUILD_WRAPPER)] && $::env(FPGA_BUILD_WRAPPER) ne ""} {
    set wrapper [file normalize $::env(FPGA_BUILD_WRAPPER)]
}
add_file $wrapper
set handle [open [file join $script_dir sources.list] r]
set sources [split [string trim [read $handle]] \n]
close $handle
foreach src $sources { add_file [file join $root [string trim $src]] }
if {$profile eq "hdmi"} {
    set handle [open [file join $script_dir hdmi_sources.list] r]
    set hdmi_sources [split [string trim [read $handle]] \n]
    close $handle
    foreach src $hdmi_sources { add_file [file join $root [string trim $src]] }
}
add_file [file join $root constraints $cst]
add_file [file join $root constraints $sdc]
set_option -top_module $top_module
set_option -output_base_name instrument
# Gowin writes impl/ relative to cwd, even when the GPRJ lives elsewhere.
# Keep outputs inside this run and provide the relative include headers.
set project_work [file join $run_dir instrument]
file mkdir [file join $project_work rtl audio]
foreach header [glob -directory [file join $root rtl audio] *.vh] {
    file copy -force $header [file join $project_work rtl audio [file tail $header]]
}
cd $project_work
file mkdir [file join $project_work rtl prototypes]
foreach header [glob -directory [file join $root rtl prototypes] *.vh] {
    file copy -force $header [file join $project_work rtl prototypes [file tail $header]]
}
if {$profile eq "hdmi"} {
    set_option -place_option 2
    set_option -route_option 1
}
run all
