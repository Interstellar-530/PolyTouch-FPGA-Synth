# Instrument RTL

Current milestone: `top.v`

- `clk_27m`: H11, Dock 3714 27 MHz oscillator.
- `hp_bck/hp_ws/hp_din`: N15/P16/P15, on-board PT8211 debug DAC.
- `pa_en`: R16, headphone amplifier enable.
- `led`: N16.

The first build is intentionally limited to one DDS voice with a repeating ADSR
gate. It does not yet contain touch, ADC, PCM5102A, or multi-voice mixing logic.
The build adds `rtl/audio` as the synthesizer include path. `dds_osc.v` therefore
loads `wave_sine.hex` with `$readmemh("wave_sine.hex", ...)` in both
Gowin IDE and Tcl builds.
