// Reference drives I2S directly; PLL output is4x compute only.
create_clock -name clk_ref -period 81.380 [get_ports {clk_12m288}]
create_generated_clock -name clk_compute -source [get_ports {clk_12m288}] -multiply_by 4 [get_pins {u_audio/u_clock/u_pll/CLKOUT}]

// Only the first stages of the two toggle synchronizers are asynchronous.
// Keep meta->sync and all other inter-clock paths timed.
set_false_path -from [get_regs {u_audio/u_bridge/request_toggle*}] -to [get_regs {u_audio/u_bridge/request_meta*}]
set_false_path -from [get_regs {u_audio/u_bridge/result_toggle*}] -to [get_regs {u_audio/u_bridge/result_meta*}]

// Bundled sample data is held until the next frame (>20us). Its destination
// captures only after the result tag traverses two audio-clock registers
// (at least two reference periods after publication). Same-edge hold is not
// a functional transfer. Keep the default, stricter setup check on this bus.
set_false_path -hold -from [get_regs {u_audio/u_bridge/sample_hold*}] -to [get_regs {u_audio/u_bridge/sample_audio*}]
