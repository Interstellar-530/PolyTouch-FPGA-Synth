# Changelog

## 2026-10-08

- Checked the previous handoff package: 50 files matched their manifest
  SHA256 values.
- Fixed the `.gprj` existence check in `build_instrument.tcl`.
- Added and debugged the LED2 blink indicator on Orange_LED2, N16.
- Added a four-LED 27 MHz diagnostic and an internal-OSC diagnostic.
- Confirmed the 27 MHz clock restores after reseating the core board.
- Restored the normal single-voice DDS + ADSR + PT8211 design.
- Confirmed `SRAM Program`, operation 2, succeeds.
- Confirmed `SRAM Program and Verify`, operation 4, fails with verify error
  `0x00006020`; all future SRAM programming uses operation 2.
- Added `source/rtl/gao_top.rao` and integrated a GAO core.
- Generated `artifacts/ao_0.fs` with the GAO core.
- Diagnosed the standalone GAO launcher and jtagserver conflict.
- Added the 2026-10-08 debug log and PDF.
- Updated the board documentation set with datasheets, schematics, GAO manual,
  and Programmer manual.
- Updated global and project AGENTS.md, created the 2026-10-07 archive, and
  cleaned project temporary files.

## 2026-10-10
- Rebuilt the normal design without GAO; verified no GAO/OSC resources in the report.
- Added T3/T2 user-key tone switching: T3 -> C4 261.63 Hz, T2 -> C5 523.25 Hz, default A4 440 Hz.
- Reduced PT8211 output by >>>2, about -12 dB.
- Programmed SRAM with operation 2; User Code 0x00006AE4. Read Device Codes succeeds.
- Verified Gowin key executables and GAO IP core files are present.


## 2026-10-10 修订二：连续发声与 PT8211 位对齐

听众反馈两个问题：播放时背景噪声大，以及不切换按键时会出现 0.25 秒通断的警报式嗡鸣。两处根因都已经定位并修改。

- `source/rtl/top.v`：删掉 0.25 秒通断门控和 `gate_cnt`。复位释放后 `gate` 恒为高，ADSR 走完起音、衰减后停在延音电平并一直保持；按键只改变 DDS 的频率控制字，不再周期性静音。
- `source/rtl/audio/pt8211_tx.v`：按 Sipeed/Gowin 官方 `TangPrimer-20K-example/PT8211/src/pt8211_drive.v` 重写帧结构和 WS 相位。帧计数 `b_cnt` 走 0..31，`b_cnt` 为 0 和 16 时请求新字，WS 在 `b_cnt` 3 拉低、19 拉高。原来的 15/31 翻转比 DAC 期望的相位晚一个位，DAC 会按错位的符号位重组字，听感上就是叠加在音调上的严重失真。
- 新模块的 DIN/WS 在 BCK 下降沿更新，DAC 仍在上升沿采样，位流序列与官方一致，建立时间从几乎为零增加到约半个 BCK 周期。
- 用 Python 时序模型分别仿真官方驱动和新模块，两者 DAC 可见的 (WS, DIN) 序列逐点相同。
- 重新构建结果：331 LUT/ALU/ROM16、188 寄存器、1 块 BSRAM、1 个 18×18 乘法器；0 个建立违规端点、0 个保持违规端点，实际 Fmax 113.169 MHz，约束 27 MHz。构建日志不再出现 `wave_sine.hex` 找不到的警告，工程里没有 GAO 核。
- 新码流 SHA256 `0612d3383736688423204cd2a04ad2350a110d9c7c7e3f483008a6ddb2faa399`，User Code `0x00009F8A`，已用 `SRAM Program`（操作 2）写入。
