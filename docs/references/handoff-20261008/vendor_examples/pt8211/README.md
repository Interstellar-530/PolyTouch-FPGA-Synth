# Sipeed PT8211 vendor example

Source: Sipeed `TangPrimer-20K-example`, `PT8211/src/` (the demo that ships with
the Tang Primer 20K Dock). Files kept verbatim so the debug transmitter can be
compared against a known-good reference on this board.

- `pt8211_drive.v`: bit/word framing and WS placement. The project module
  `source/rtl/audio/pt8211_tx.v` reproduces this framing, but updates DIN and WS
  on the BCK falling edge so the DAC gets roughly half a BCK of setup time
  instead of zero.
- `top.v`: 27 MHz -> rPLL 6 MHz -> CLKDIV/4 -> 1.5 MHz BCK, PA_EN held high.
- `gowin_clkdiv.v`, `gowin_rpll.v`: generated Gowin IP wrappers for the above.

The vendor example advances the wavetable ROM address twice per audio frame; the
project keeps one sample per frame and feeds the same sample to both channels.
