# Flash 记录 2026-10-20

## 键控响度 v0.3 实现（10:24）

- 位流：`build/gowin_top_dbg8/runs/20261020T101047946-cdb5af8f/instrument/impl/pnr/instrument.fs`
- SHA256：`8691359FE7225D6E4044A891645B585E2E3D21280D7FBF97EB701E0A3ADF94B6`
- 指标：Logic 10895（53%）、Register 3392、BSRAM 40/46、MULT18X18 1、MULT9X9 1、Fmax 38.993 MHz、违规 0。
- 操作 37：`Program and Verify flash successfully.`，27.14 s。
- UI 重开：`D0 -> OK`、`M1 -> OK`，PID 6040。
- 门禁：按用户“跳过长门禁”使用 `-SkipSimulation`；定向 `tb_key_gain`、`tb_engine8_pitch`、`tb_top_switch`、`tb_top_pitch8` 通过；完整套件停在既有 `tb_gpio_top` 演示/手动失败。

## 追加：音色区分与音量（10:34）

- 钢琴表提亮（stage tilt 0.006+0.014、bell 0.30），钢琴包络 release 32；吉他包络 sustain 16384、decay 8，并加吉他专用 3.5 kHz 一阶低通。
- 音量：UART `V0..V100`，平方律 101 项 LUT + 24×9 乘法，0=静音、100=原始电平；UI ↑/↓ 每步 5%。
- 位流：`DB7B775DDD7A8848BB8E6F072AA61B8CECFD501D4704038D1E0C9181422DA71E`
- 指标：Logic 10899、Register 3424、BSRAM 40/46、MULT18X18 1、MULT9X9 1、Fmax 33.171 MHz、违规 0。
- Flash 操作 37：`Program and Verify flash successfully.`，26.95 s；UI `D0/M1 -> OK`（PID 21528）。
- 串口实测 `V50/V100/V0/V100` 全部 OK。
- 门禁：按用户要求跳过完整套件；定向 `tb_top_switch` PASS。
## 追加：吉他去低通 +3.5 dB（10:45）

- 移除吉他专用 3.5 kHz 低通；`global_crossfade` 在软限幅前给吉他 +3.5 dB（×1.5），钢琴直通。
- 位流：`EEC3292D6443F8BB20595BDD4DA0EB62BA55334F0032B582441F047E0CAE487E`
- 指标：Logic 10837（53%）、Register 3398、BSRAM 40/46、MULT 1/1、Fmax 33.548 MHz、违规 0。
- Flash 操作 37：27.04 s；UI `D0/M1 -> OK`（PID 25200）。
- 门禁：按用户要求跳过；`tb_top_switch` PASS。
## 追加：24 位低通定标修复（10:51）

- 根因：26 位滤波状态含 2 个保护位，输入未乘 4，稳态输出 1/4（−12 dB）。
- 修复：`mix_lp_in = {mixed_shared24, 2'b00}` 后再做差分；音量 100 恢复 unity。
- 位流：`2F8DB574A2ECABE2E71A8B6A8DA32CDAF2EF993F9198AB120CAA15B35DFC8606`
- 指标：Logic 10778（52%）、Register 3398、BSRAM 40/46、MULT 1/1、Fmax 31.386 MHz、违规 0。
- Flash 操作 37：26.89 s；UI `D0/M1 -> OK`（PID 36012）。