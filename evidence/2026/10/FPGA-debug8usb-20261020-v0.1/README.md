# PolyTouch debug8usb 构建归档（2026-10-20 v0.2）

## 配置

- 板卡：Sipeed Tang Primer 20K Dock 3714，GW2A-LV18PG256C8/I7，版本 C
- 音频：板载 PT8211，27 MHz 单时钟，46.875 kHz
- 声部：8 声部
- 输入：普通 USB 键盘经 CH9350L，`kbd_uart_rx = L9`，`kbd_uart_tx = N8`，115200 8N1
- 表情：MCP3208 CH0 接 FSR 压力，CH1 接弯音电位器；压力增益启用
- GPIO 琴键：本档关闭，释放 L9/N8 给 CH9350L
- 顶层：`top_dbg8usb_build`
- 构建档：`debug8usb`

## 构建结果

| 项目 | 结果 |
|---|---|
| Logic | 11202 / 20736（55%） |
| Register | 3596 / 16173（23%） |
| BSRAM | 40 / 46（87%） |
| DSP | 0.75 / 24（MULT9X9 1，MULT18X18 1） |
| Setup 最差裕量 | +5.893 ns，0 条负裕量 |
| Hold 最差裕量 | +0.211 ns，0 条负裕量 |
| 位流大小 | 7,264,154 字节 |
| 位流 SHA256 | `9F2A26E6EB5AD34543032A11CE5E3927171E2A08F810108841AD7648620AB542` |

## 关键引脚

| 信号 | 引脚 |
|---|---|
| 27 MHz | H11 |
| PT8211 BCK / WS / DIN | N15 / P16 / P15 |
| PA_EN | R16 |
| CH9350L RX / TX | L9 / N8 |
| MCP3208 CS / SCK / MOSI / MISO | N6 / D11 / A11 / B11 |
| BL702 UART TX / RX | M11 / T13 |
| LED | N16 / N14 / L14 / L16 |

## 输入行为

普通 USB 键盘的键位映射沿用电脑端布局：下层 `Z S X D C V G B H N J M`，上层 `Q 2 W 3 E R 5 T 6 Y 7 U`，PageUp/PageDown 升降八度，Esc 全松键，F1–F5 钢琴硬度，F6 切换钢琴/吉他。键盘事件使用固定力度 100；当前第二维由 FSR 压力提供，压力是全局 VCA 控制，不是逐键触后。

## 验证状态

- `tb_host_kbd`：PASS，覆盖按下/松开、去重、和弦、移调、Esc、F1、截断帧重同步、rollover。
- `tb_pressure_bend`：PASS，640 个压力 tick 与 4096 个弯音 ADC 码逐值匹配，t90=5 control ticks。
- `tb_gpio_top`：PASS。已修复演示模式下 GPIO Note Off 未被消费、阻塞下一次 Note On 的问题。
- `tb_audio_capture`：PASS，完整捕获 58,880 个原生 PT8211 帧，覆盖 UART、ADSR、四音和弦、松键、M0/M1 与数字静音。
- 完整门禁仍有 13 个历史/原型测试失败，另有 5 个测试台文件在仓库中缺失并被明确跳过。失败列表见 `evidence/gate_summary.txt`；它们不在本次 USB 键盘 + FSR 定向验收范围内，但在烧录比赛固件前仍需逐项处理或确认过时。

## 边界

- 尚未上板烧录音频；需要实际 USB 键盘、CH9350L 和 FSR 接线后验证。
- 键盘到音频的端到端延迟尚未测量；普通 USB 键盘的 CH9350L 扫描周期和 FSR 标定需要实测。
- FSR 目前控制全局 VCA；赛题要求的“自研交互”与 10ms 延迟仍需现场证据。
- 这不是完整采样播放器，音频仍是 FPGA 实时波表合成，符合赛题对预录 PCM 的限制。
- 13 个历史/原型失败不应当被“构建成功”掩盖；该位流可用于 bring-up，不应直接作为最终比赛固件。

## 复现

在主仓库 `output/handoff_milestone2_20261008/source` 下执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\build.ps1 -Profile debug8usb
```

完整门禁（包含长时捕获）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_simulation.ps1 -Iverilog D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\iverilog.exe -Vvp D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\vvp.exe
```

其余门禁（长时捕获已单独完成后）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_simulation.ps1 -SkipAudioCapture -Iverilog D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\iverilog.exe -Vvp D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\vvp.exe
```