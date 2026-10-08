# Competition Requirements Summary

Source: `reference/competition/高云半导体.pdf` and
`reference/competition/FPGA创新设计赛道通知.pdf`.

## Basic Requirements

- At least two independently controllable performance dimensions.
- Complete sample-by-sample audio synthesis in FPGA HDL.
- Control-to-audio latency <= 10 ms.
- At least 4 voices.
- Independent phase accumulator, frequency control, and envelope per oscillator.
- Real-time pitch change, ADSR, and multi-voice mixing.
- I2S output to a DAC.
- No recorded PCM, no pre-rendered stream, no full-song playback.

## Expanded Requirements

- 32 voices, or >=32 additive components per note, or parallel physical-model
  units.
- Three or more expressive dimensions.
- Two or more instrument timbres.
- Hardware effects such as chorus, delay, or reverb.
- Latency <= 5 ms with deterministic jitter.
- Hardware-generated visualization or performance feedback.

## Scoring Core

`throughput = active independent oscillator count x actual output sample rate`

- Increasing internal oversampling does not add score.
- A wavetable lookup counts as one oscillator.
- Additive synthesis counts its components.
- FM counts its modulation operators.
- Physical modeling counts parallel string/modal units.

## Required On-Site Evidence

- Test mode with multiple different frequencies.
- Spectrum shows independent peaks.
- RTL proves the real-time generation path.
- No pre-recorded PCM.
