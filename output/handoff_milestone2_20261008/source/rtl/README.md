# Instrument RTL

Current milestone: four-voice polyphony with a built-in test tune.

v1.0.0 publishes the previously programmed SRAM 0x5633 functional baseline
with clarified comments. See the repository-root README and
`docs/releases/v1.0.0-code-guide.md` for the Chinese code guide and
`docs/releases/v1.0.0-validation.json` for release verification.

- `top.v`: wiring, reset tree, key handling, LED indicators.
- `audio/note_phase_inc.v`: MIDI note to 32 bit phase increment.
- `audio/dds_osc.v`: interpolating single-cycle wavetable oscillator.
- `audio/adsr.v`: envelope with parameterised step sizes.
- `audio/poly_voice.v`: one voice (oscillator, envelope, velocity).
- `audio/event_fifo.v`: note event queue between the sequencer and the allocator.
- `audio/voice_alloc.v`: four-voice allocator, the keyboard interface.
- `audio/song_player.v`: test tune sequencer with two chord sets.
- `audio/mixer.v`: sum, master level, saturation, smoothing.
- `audio/uart_ctrl.v`: serial note control.
- `audio/pt8211_tx.v`: on-board PT8211 debug DAC transmitter.

[S2-AI] Added during task S2 on 2026-10-14:

- `audio/gpio_keyboard.v`: 12-key input layer. Two-stage synchroniser, per-key
  debounce (1 ms press, 3 ms release at 27 MHz), edge detection, a two-deep
  per-key event queue and a single-event output with a ready handshake. A
  burst of simultaneous changes is submitted release-first, then press.

[S3-AI] Added during task S3 on 2026-10-14 (author: deepseek, for later review):

- `audio/clk_params.vh`: the single source of truth for clock and sample-rate
  parameters. Two profiles: the 12.288 MHz / 48 kHz standard profile for
  PCM5102A standard I2S, and the 27 MHz / 46.875 kHz debug profile for the
  on-board PT8211 path. It also lists, as a checklist, every module that still
  carries 27 MHz / 46.875 kHz constants and must be revisited when the system
  clock is migrated.
- `audio/i2s_tx.v`: parameterised standard I2S (Philips) transmitter. All state
  updates in `posedge clk`; BCK comes from an integer counter (4 system cycles
  per BCK in the standard profile, 9 with 4 high / 5 low in the debug profile),
  never from a phase accumulator or a derived clock. DIN and LRCK only change on
  BCK falling edges, position 0 of each channel is the zero-delay bit, then
  `DATA_BITS` (16 or 24) bits MSB first, then zeros. Samples are latched once per
  frame boundary, so a mid-frame change cannot tear the frame. After reset the
  first complete frame is forced to zero and latching starts at the next
  boundary (E0/E1 rule). `sample_tick` is one clock wide on every frame boundary
  where LRCK falls. Illegal parameter sets are rejected at time 0 under
  `\`ifdef SIMULATION` with an `S3_PARAM_INVALID` reason.

The transmitter is deliberately **not** instantiated in `top.v`: the production
bitstream and the on-board PT8211 path are untouched. When it is wired in later,
tie `i2s_tx.rst` to the power-on reset only; runtime mute (M0) and panic must
zero the left/right inputs instead of asserting `rst`, because stopping BCK and
LRCK makes the DAC mute and re-lock. The isolated synthesis entry for the module
is `build/build_i2s_tx.ps1` (wrapper `build/isolated/i2s_tx_top.v`, project and
reports under `tmp/gowin_i2s_tx/`); it is a build-only project with its own
pin assignment and does not change the production CST.

Simulation added in S3: `sim/i2s_rx_model.v` (PCM5102A receive model that only
observes BCK/LRCK/DIN, discards partial halves and reports one pair per frame),
`sim/i2s_tx_checker.v` (one self-checking box per profile/width combination:
vectors, seeded PRNG, mid-frame disturbance, digital mute, three hard resets at
left-data / right-data / padding positions, plus offset, channel-swap and
single-bit negative controls on the captured slots), `sim/tb_i2s_tx.v` (four
combinations at 12.288 MHz and 27 MHz, 16 and 24 bits, >=264 data frames each,
and a hand-built bit string that validates the receive model itself) and
`sim/tb_i2s_tx_params.v` (five illegal parameter sets). The gate now runs
thirteen positive testbenches plus those five expected-failure parameter runs;
a parameter run only counts as passing when it exits non-zero *and* prints the
matching reason.

Pins:

- `clk_27m`: H11, Dock 3714 27 MHz oscillator.
- `hp_bck/hp_ws/hp_din`: N15/P16/P15, on-board PT8211 debug DAC.
- `pa_en`: R16, headphone amplifier enable.
- `led`: N16, run indicator. `led_chord`: N14, chord set indicator.
- `key_rst` D7, `key_s1` T3, `key_s2` T2. `key_s4`/B10 is RECONFIG_N.
- `uart_tx` M11, `uart_rx` T13, the BL702 USB-UART bridge on bank 2.
- [S2-AI] `gpio_key_n[11:0]`: twelve active-low keys, one per C4..B4 semitone,
  with external 10 kOhm pull-ups to 3.3 V. Pin map and the 3.3 V bank note are
  in `docs/hardware/FPGA-pinplan-20261013-v0.1.csv` and the CST comments; the
  CST entries still need a Gowin place-and-route review before wiring the board.

On power-up the built-in tune runs. Sending `N1`..`N127`, `O1`..`O127`, or
`X` enters manual mode and clears queued demo notes. `D0` selects manual mode
explicitly; `D1` clears active voices and restarts the tune. `M0`/`M1` mute
or unmute the DAC stream without changing mode. Commands use 115200 8N1,
end with CR or LF, and receive `OK` or `ERR`. The old `F` command is rejected.
The host should wait for each reply before sending the next command; a
16-entry reply queue absorbs short bursts and counts overflow.

Nothing here uses a soft CPU: every sample is generated by RTL. The twelve
GPIO keys are wired through their own input layer and a 16-entry manual event
FIFO, so a multi-key burst no longer touches the sparse UART event seam.
Optional touch (MPR121), the pressure ADC and standard I2S to PCM5102A are
still to come.

[S2-AI] Manual-input rules added in S2: a key press leaves the built-in tune
and takes over, the press is delivered within about 1 ms of the pin going low,
panic (`X`) and the mode commands (`D0`/`D1`) drop unsent manual events and
re-arm the keys so a held key must be released before it sounds again, and a
key *release* during the demo is dropped instead of queuing, because entering
the demo already released every voice.

Each accepted Note On also produces a one-clock `v_start` pulse for the chosen
voice. `poly_voice` keeps that pulse until the next audio sample tick, then
restarts its ADSR attack and oscillator phase together. A repeated held note
uses its existing voice; otherwise the allocator prefers an idle voice, a
releasing voice, then the oldest held voice. Relative age ranks avoid counter
wrap during long performances. The twelve self-checking testbenches in
`../sim/run_simulation.ps1` (ten from S1 plus `tb_gpio_keyboard` and
`tb_gpio_top` from S2) must pass before any programming.


## S3 独立复核（2026-10-14）
保留 DeepSeek 原实现标签，Codex 修正处以 S3-REVIEW 标记。最终十三台正向、六个参数负例、三种检查器故障注入及原音频回归通过；真实16/24位隔离综合的资源分别为93逻辑/68寄存器、125逻辑/92寄存器。复位模型在BCK停止时清配对，复位测试保持两路非零探针，填充位/tick边界有强制断言。头文件统一新模块默认值，Gowin产物限于临时工程。原阶段24位报告与复位覆盖结论以 docs/evidence/FPGA-S3-review-20261014-v0.1.md 为准；生产顶层仍未接入I2S。
