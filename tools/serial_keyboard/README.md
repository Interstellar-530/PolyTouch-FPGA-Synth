# PolyTouch 电脑演奏窗口

关闭 PuTTY 等占用 COM13 的串口工具，双击 `open-keyboard.cmd`。窗口自动连接 COM13、115200 8N1，进入手动模式并解除数字静音。按住 A/W/S/E/D/F/T/G/Y/H/U/J/K 发 C4 到 C5，松开该键发 Note Off；A、D、G 是 C 大三和弦，H 是 A4。当前 FPGA 只有四声部，窗口能记录更多按键，但第五个音会触发声部窃取。

按钮可切换手动/演示、全松键和静音。空格也会全松键；手动时失去焦点会全松键，关闭窗口会等待 X 应答再释放端口。全松键后仍按住的键被抑制，要松开后重新按下。演示模式中按新的音符键会先切回手动。输入设备的多键识别能力取决于电脑键盘，部分键组合可能受键盘自身限制。

D0 本身只是进入等待音符的手动状态；这个窗口将真实按下/松开转换成既有 N/O ASCII 命令。固件必须支持 D0/D1，模式修复版 User Code 为 0x5633；旧 Flash 0xFCF0 在断电后加载，需重新加载模式修复版到 SRAM。GUI 下方显示设备的 OK/错误应答，运行记录保存到 `output/serial_keyboard/`。

运行环境是 Windows PowerShell 5.1 与系统 .NET Framework，使用 WinForms 和 SerialPort，无需 Python或新增第三方运行库。本轮实现是本项目电脑端代码；资料调研中的其他合成器只作交互思路参考，没有复制其源码。音频依然完全由 FPGA 实时生成，电脑端没有合成/播放音频。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\serial_keyboard\keyboard.ps1 -SelfTest
# 关闭串口窗口后才运行实机检查：
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\serial_keyboard\keyboard.ps1 -SmokeTest -Port COM13
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tools\serial_keyboard\keyboard.ps1 -Port COM13
```

自检覆盖按下/松开、自动重复、和弦、原始音高的松键以及 Panic 清除积压事件。实机检查验证 D0/M1、三音和弦 N/O 和关闭时 X 的全部 OK 应答。用户已验证实际按下、松开和和弦；电脑输入到模拟声音的实际延迟尚未测量。完整硬件连接方案见 `docs/hardware/FPGA-硬件连接与演奏操作-20261013-v0.1.md`。
