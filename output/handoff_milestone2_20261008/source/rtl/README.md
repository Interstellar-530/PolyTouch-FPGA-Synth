# Instrument RTL

Current milestone: `top.v`

- `clk_27m`: H11, Dock 3714 27 MHz oscillator.
- `hp_bck/hp_ws/hp_din`: N15/P16/P15, on-board PT8211 debug DAC.
- `pa_en`: R16, headphone amplifier enable.
- `led`: N16.

The current build is limited to one DDS voice. The ADSR gate is held high after
reset, so the voice attacks, decays to sustain and then holds that level; two
user keys switch the DDS frequency word. It does not yet contain touch, ADC,
PCM5102A, or multi-voice mixing logic.

