# 优化 07：CH9350L 长按与断线策略

日期：2026-10-22。结论：软件侧的“持键期间不被静默超时误清音”策略已经实现并通过定向仿真、既有 HID 回归和两档 Gowin 构建；真实 CH9350L 长按、空闲和拔线帧尚未抓取，因此第 7 项整体仍不能标记为硬件验收完成，也没有烧录。

## 策略

`host_kbd_input` 新增编译期参数 `TIMEOUT_POLICY`，默认值为 `1`：

| 取值 | 行为 | 用途 |
|---:|---|---|
| 0 | strict：任何 `WATCHDOG_MS` 静默超时都传到 `hid_keymap` 并清键 | 保留旧行为，供硬件排查或确认心跳可靠后选用 |
| 1 | idle-only：仅无持键时接受静默超时；持键期间忽略静默超时 | 默认，避免 state 2 不长按周期发帧时误清长音 |

`0x86` 设备拔出通知不受策略影响，仍然无条件立即清音。顶层新增编译期参数 `HOST_KBD_TIMEOUT_POLICY` 并透传到 `host_kbd_input`，端口和 UART 协议没有变化。默认 `WATCHDOG_MS` 仍为 2000ms。

## 修改范围

生产修改仅涉及 `rtl/audio/host_kbd_input.v`、`rtl/audio/hid_keymap.v` 注释和 `rtl/top.v` 的参数透传。新增 `sim/tb_host_kbd_timeout.v` 并注册到 `sim/run_simulation.ps1`。没有修改音频计算、波表、I2S、UART 命令格式或实体引脚。

## 验证结果

| 测试 | 结果 | 覆盖内容 |
|---|---|---|
| `tb_host_kbd_timeout` | PASS | idle-only 持键后连续 5 秒无心跳仍保持；strict 同时清键；0x82 心跳恢复；0x86 拔出清键后可重按 |
| `tb_host_kbd` | PASS | 原按下/松开、去重、和弦、移调持音、Esc、截断帧重同步、FIFO 回绕 |
| `tb_top_host_ctrl` | PASS | `HOST_KBD_ENABLE=1` 顶层路径、首键、和弦、F6、音量上下界、Esc |

专用测试台使用 1MHz/100kbaud 等比例时钟和 20ms watchdog，使 5 秒静默场景能在可接受时间内完成；生产参数仍为 27MHz 和 2000ms。三台 Icarus 仿真均在沙箱外运行，编译器无诊断输出并退出 0，运行日志保存在 `logs/`。

## Gowin 构建

| Profile | Logic | Register | BSRAM | DSP | Fmax | Setup | Hold | 负裕量端点 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `standard27` | 11406 | 3674 | 25/46 | 1.75/24 | 38.557MHz | +11.102ns | +0.211ns | 0/0 |
| `debug8usb` | 11378 | 3702 | 25/46 | 1.75/24 | 35.885MHz | +9.171ns | +0.319ns | 0/0 |

`debug8usb` 的 v2.1.0 公布基线为 Logic 11392、Register 3702、BSRAM 25/46、DSP 1.75、Fmax 37.890MHz、setup +10.645ns、hold +0.208ns。本次 Logic 少 14、寄存器与 DSP 不变，Fmax 仍远高于 27MHz；`debug8usb` 最差路径是原有 `ev_q_word` 到声部分配器 `v_note` CE，不是新增超时 mux。标准 27MHz I2S 档本轮也完成了 PnR，最差建立路径同样不在键盘策略逻辑上。

## 复现

在项目根目录运行：

```powershell
powershell -File docs\evidence\FPGA-优化07-长按断线策略-20261022-v0.1\commands\reproduce.ps1
```

需要重做两档 Gowin 构建时加 `-RunBuild`。脚本默认使用本机 Icarus 和 Gowin 路径，可通过参数覆盖；临时目录在运行结束后按明确路径清理。

## 边界与回退

本次没有实体 CH9350L，无法完成文档要求的 10 秒实体长按、真实空闲和拔线帧验收，也不能确认 state 2 是否周期发送 `0x82`。如果实测没有心跳且拔出时也不发送 `0x86`，idle-only 在持键拔出场景仍可能留下粘音，这是当前最大剩余风险。正式烧录前仍需完整仿真门禁和实体外设测试。

回退可设置 `HOST_KBD_TIMEOUT_POLICY=0` 恢复严格超时，或撤回三个生产 RTL 修改并重新构建。位流和构建凭据不能跨源码回退继续使用。Gowin 构建产物、报告和位流 SHA256 见 `results.json` 与 `build/`，临时 `.vvp` 不归档。
