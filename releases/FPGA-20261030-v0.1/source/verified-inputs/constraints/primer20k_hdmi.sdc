// 27 MHz ?? I2S ??????? 27 MHz ?????H11?GCLKT_0???????
// ?????BCK = clk/9 = 3.000 MHz?? 4 ??? 5 ????? 64 ? BCK?
// LRCK = clk/576 = 46.875 kHz???????????????????????
// 27 MHz ??????????? 48 kHz?49.152/27 = 2048/1125???????
// 46.875 kHz ?????12.288 MHz ?? constraints/primer20k_i2s.sdc?
// UART ??? 234 ?/??115200 ????? 115 384??? 0.16%??
create_clock -name clk_27m -period 37.037 [get_ports {clk_27m}]

// The 1 kHz dashboard snapshot crosses from the 27 MHz audio clock into the
// 74.25 MHz pixel clock. Its multi-bit data is stable before the synchronized
// toggle changes, so the two independent clock groups are asynchronous.
create_clock -name pix_clk -period 19.493177 -waveform {0 9.746589} [get_pins {u_hdmi/u_hdmi_clock/u_clkdiv/CLKOUT}]
set_clock_groups -asynchronous -group [get_clocks {clk_27m}] -group [get_clocks {pix_clk}]
// Board 32-voice core. Events, controls, frames and UI use held-bus handshakes.
create_clock -name compute_clk -period 18.518519 -waveform {0 9.259259} [get_pins {u_top/u_ram32/u_clock/u_pll/CLKOUT}]
set_clock_groups -asynchronous -group [get_clocks {clk_27m}] -group [get_clocks {compute_clk}] -group [get_clocks {pix_clk}]
