# 第三项：无需新增硬件的音色控制

2026-10-16，基于第二项 f646e0f 实施。板载 S1 长按循环权重 0、64、160、255，上电默认 64；短按在松开后切伴奏。长按达到门限只触发一次，松开不再补短按。两档统一使用 20 ms 消抖，长按从消抖成立后计 600 ms，所以实际手指按下至切换约 620–621 ms。S2 保持速度功能，S3 保留音色设定。切换后一秒，现有速度 LED 临时显示四档编号；UART 任意权重显示最近预设编号。

新增串口 T0～T255，沿用 115200、8N1、CR/LF 结束和 OK/ERR 应答，大小写均可。T 命令不改变模式、音高、音符队列或包络。原 N/O/X/M/D 命令保持语义。同拍冲突时 UART 优先于板载长按。新电脑窗口提供四档按钮和滑条；滑条最多每 40 ms 提交一次目标，队列仅保留最新未发送音色请求，音符优先。主机显示目标值，不回读板上状态，连接也不自动覆盖板上音色。音色请求在 Panic 时清除，防止积压请求随后生效。

全局混合器按每个 sums_valid 音频帧向目标移动一级，完整 255 级理论上限为标准档 5.3125 ms、调试档 5.44 ms，不增加音频帧流水延迟。切换期间保持四声部相位推进和 ADSR，不重新起音。已有压力音量与弯音路径保持分工。两张波表混合形成四个预设，不声称四套独立乐器音源。

为降低连续权重的资源消耗，先将 A×(255-w)+B×w 等价变换为 (A<<8)-A+(B-A)×w，再把 20 位有符号差值拆成 18 位低部与 -2～2 的高部；高部用移位和选择修正，真正的可变乘法只剩 18×9。中间差值、乘积和求和显式留足符号位，保留原来的权重和 255、舍入及饱和行为。没有新增 ROM、声部或外部引脚。

Gowin 1.9.11.03 同条件标准档综合对比：

| 实现 | Logic | Register | MULT18X18 | MULTALU36X18 | DSP宏块等效 | BSRAM |
|---|---:|---:|---:|---:|---:|---:|
| 直接双乘法 | 3977 | 1509 | 2 | 7 | 8 | 2 |
| 20位单乘法 | 3933 | 1496 | 2 | 6 | 7 | 2 |
| 最终18位拆分 | 4065 | 1509 | 2 | 5 | 6 | 2 |

采用最终方案，以增加 88 个逻辑单元换取相对双乘法减少 2 个 DSP 宏块等效预算，给未来声部和效果器留余量。Logic 为 4065/20736，BSRAM 为 2/46；DSP 等效按 MULTALU36X18 为一块、MULT18X18 为半块计算，最终物理放置仍由 PnR 确认。报告是综合结果，不是布局布线或实机时序结论。Gowin 综合报告使用默认 100 MHz 估算，不能据其中默认时钟的 slack 宣称实际 12.288 MHz 约束已通过。

8 项定向 RTL 测试全部通过，结果在 results.json。新增音色数值测试覆盖全部 256 权重、正负满量程及反向极值、随机分量，共 37370 帧，与独立 64 位整数参考逐位一致。受控分量 A=12000、B=-8000 时，直接切换跳变 9961 LSB，逐帧平滑最大 40 LSB；该值描述控制引入的跳变，不是实物爆音或声压结论。8位权重每帧一级已是此精度下最小非零步进，更细平滑需要提高权重精度或延长过渡。

顶层测试使用真实 UART 位流、MCP3208 模型及独立 I2S 解码器，四声部持续按住：1183 帧解码，其中 1103 帧非零，267913 次逐周期相位检查通过；从 T 命令生效后的采样点量得 0→255 过渡 5.294981 ms。顶层按键测试为缩短仿真，将长按和消抖门限缩短，真实默认时长与不重复触发由控制器测试验证。既有模式、S1/S2、压力顶层与标准 I2S 定向回归也通过；I2S 回归解码 8621 帧，压力 RMS 高低比仍为 3.999443。

另两项回归 tb_pressure_gain、tb_shared_engine 通过，详见 regression/。构建两档 RTL 编译及 13 项脚本检查通过，详见 build-regression/。电脑端在 Windows PowerShell 5.1 自检通过，窗口已离屏渲染视觉检查，没有打开串口；keyboard-preview.png 是连接前预览。

为区分响度与音色，直接将两张 512 点 ROM 的一个周期送入混合器，记录实际 RTL 输出并做相干 FFT。标准采样率下这个隔离测试基频为 93.75 Hz，不是实际 C4 的整机测量。四档 2～16 次谐波相对基波幅度比依次约 0.00069%、12.234%、37.396%、76.443%，频谱能量重心单调增加。亮波表含谐波是设计目标，这些数字不能当作 DAC 失真指标。测试均未削波，但 RMS 随音色变化；全幅四声部的既有余量问题仍需后续处理，未用额外补偿增益掩盖它。

资源测量还发现并修复第二项的工作目录问题：Gowin 的 impl 输出跟随 cwd，原 Tcl 最后 cd root 会写入 source/impl。现在进入独立工程目录，并复制全部相对 include 的 .vh 文件。真实综合确认输出位于本次目录的 instrument/impl/gwsynthesis。首次发现问题的综合刷新了原有 source/impl/gwsynthesis 中间文件；旧 source/impl/pnr 位流时间未变，原目录属于既有构建缓存，保留且不自动选作烧录文件。

复现时在仓库根目录执行，下方 Python 可用 Codex 捆绑运行时：

```powershell
& '<Python路径>' tools/verify_timbre.py
& '<Python路径>' tools/run_pressure_verification.py --only tb_pressure_gain tb_shared_engine --out docs/evidence/FPGA-音色控制-20261016-v0.1/regression
& '<Python路径>' tools/verify_build_profiles.py --out docs/evidence/FPGA-音色控制-20261016-v0.1/build-regression
& '<Python路径>' tools/measure_timbre_resources.py
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -File tools/serial_keyboard/keyboard.ps1 -SelfTest
```

本轮检索了 Fynthesizer、XLS32 等公开 FPGA 合成器，仅参考现有按键、串口调参思路，没有复制外部代码或新增依赖。实现与证据归档到 archive/FPGA-20261016-v0.4，可单独 revert 本项提交回退。注意回退也会恢复被本项纠正的构建工作目录问题。

没有运行完整仿真门禁、PnR 或烧录，也未推送 GitHub。临时目录限定为 tmp/timbre-implementation、tmp/timbre-verification-20261016、tmp/timbre-resource-20261016、tmp/pressure-verification-20261016、tmp/build-profiles-verification-20261016，结束前逐一核对路径并删除；保留源文件、复现工具、关键日志、频谱数据、窗口预览和归档。额度持续从本会话最近的 rate_limits 记录检查，低于剩余 15% 时保存暂停，本轮结束快照另存。第三项完成后等待用户继续指令。
