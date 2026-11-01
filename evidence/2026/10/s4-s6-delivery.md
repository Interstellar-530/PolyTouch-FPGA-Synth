# S4–S6 数字交付索引（2026-10-14）

本次工作基于队友仿真副本记录的 GitHub `main@55528a1b7999ee5e0c7a21b04ebd2d3a1fdda62`，并保留其 `fix/m2-build-issues@3a31eb2` 工作树覆盖。线上 fetch 在当前沙箱因 DNS/线程限制未能再次访问；来源提交、工具版本和基线日志见 `docs/evidence/teammate-simulation/`。

| 任务 | RTL / 模型 | 自检与参考 | 状态 |
| --- | --- | --- | --- |
| S4 MCP3208 | `source/rtl/audio/mcp3208_spi.v`、`source/sim/mcp3208_model.v` | `source/sim/tb_mcp3208_spi.v`、`docs/evidence/s4-mcp3208.md` | RTL/模型交付；2026-10-15 复核修正 19 拍帧对齐，见 `s4-review-20261015/README.md`；实物待验收 |
| S5 压力/弯音 | `source/rtl/audio/pressure_bend.v` | `source/sim/tb_pressure_bend.v`、`source/tools/pressure_bend_ref.py`、`docs/evidence/s5-pressure-bend.md` | 定点参考通过；实物待验收 |
| S6 双表/混音 | `source/rtl/audio/wavetable_rom_dual.v`、`source/rtl/audio/wavetable_osc_dual_s6.v`、`source/rtl/audio/mixer_s6.v` | `source/sim/tb_s6_audio.v`、`tools/generate_wavetables.py`、`tools/s6_reference.py`、`docs/evidence/s6-audio.md` | RTL/参考通过；Gowin IP/PnR/实机待验收 |

三台新增测试已加入 `source/sim/run_simulation.ps1`；2026-10-15 的 S4 复核又补入 `tb_mcp3208_i2s_coexist` 与 `tb_mcp3208_params`，完整门禁包含 14 台（原 9 台基线 + S4–S6 三台 + S4 复核两台）。Python 参考、ROM 深度/范围/SHA 检查已在本机通过；S4、S5、S6 的 VVP 均实际退出 0 并报告 PASS。S4 复核时确认当时的 access violation 来自运行环境而非 Icarus 本身：把 `D:\NanjingUniversity\FPGA\msys64\ucrt64\bin` 放进 PATH 后在沙箱外运行，`iverilog` 与 `vvp` 均干净退出 0；脚本仍会清理每台测试的 `.vvp` 临时文件。

S4–S6 都是独立数字交付，尚未接入外部 PCM5102A、MCP3208 实物、GPIO/FSR、CST/SDC 或顶层正式时钟；因此不改变任务清单中 T04 的实机验收状态。
