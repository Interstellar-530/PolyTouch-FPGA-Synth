# 12.288 MHz reference; the rPLL derives the 73.728 MHz compute clock.
create_clock -name clk_ref -period 81.380208 -waveform {0.000000 40.690104} [get_ports {clk_ref}]
