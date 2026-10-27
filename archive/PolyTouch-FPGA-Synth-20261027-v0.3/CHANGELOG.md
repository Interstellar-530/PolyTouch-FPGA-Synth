# v0.3 changes

- Added HDMI fail-safe handling to the PC serial transport: disposal sends `X` then `R1`, and an unexpected worker exit attempts one final `R1` before closing the port.
- Added F7 key-repeat protection; the route changes once per physical F7 press and the latch resets on key-up or window deactivation.
- Ran the serial regression without the earlier Icarus access violation: 80 positive benches and 6 I2S parameter negative cases passed.
- Ran the long `tb_audio_capture` bench separately: 58,880 PT8211 frames passed.
- Kept the v0.2 dashboard protocol and HDMI route implementation, with updated PC sources and evidence.
