# 32-voice RAM prototype: 49.152 MHz compute clock, 1024 clocks per 48 kHz frame.
create_clock -name clk -period 20.345 -waveform {0.000 10.1725} [get_ports {clk}]
