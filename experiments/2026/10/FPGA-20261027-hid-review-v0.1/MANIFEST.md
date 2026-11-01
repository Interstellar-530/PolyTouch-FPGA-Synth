# PolyTouch-FPGA-Synth 2026-10-27 v0.3

This archive records the HDMI dashboard profile with the computer dashboard route, F7 display switching, serial-disconnect HDMI fallback, and F7 key-repeat protection.

The FPGA protocol remains `R0` for the computer dashboard, `R1` for HDMI, and `Q` for the live status/visual snapshot. The PC transport now queues `X` followed by `R1` during normal disposal and makes a best-effort `R1` write if the worker exits unexpectedly. The WinForms window latches F7 until key-up or focus loss so Windows key repeat cannot toggle the route repeatedly.

The archive contains the current RTL, HDMI wrapper, simulation suite, PC window sources, build inputs, regression evidence, reproduction commands, and SHA256 records. No new bitstream is included because Gowin PnR was unavailable in this runtime.
