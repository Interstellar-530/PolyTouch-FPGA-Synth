# S1 真实音频捕获与频谱验收

`tb_audio_capture.v` 实例化当前 `top`，按真实 27 MHz 时钟运行，通过 UART RX 引脚发送 `D0/N/O/M` 命令。它不强制 `sample_tick`，也不直接注入声部事件。接收端只用 `hp_bck/hp_ws/hp_din` 的边沿解码 PT8211 16 位右对齐数据，检查 BCK 每18时钟、每声道16位、每帧576时钟及采样使能单周期；内部 `frame_data` 仅作串行结果的独立对照，不参与位序判定。

捕获包含静音、A4稳态、A4释音、C4/D#4/F#4/A4四音、依次松开前三音、全部释放、四音仍按住时M0静音、M1恢复，共58880个双声道采样。A4稳态32768点，其余频谱窗口4096点；独立声部的门控、音符号和idle状态逐帧检查。S1 将门禁从九项增加为十项，S2 又加入两台 GPIO 自检，当前共十二项，实际清单以 `sim/run_simulation.ps1` 为准。

`analyze_audio_capture.py` 校验文件格式、各段数量、段内帧连续、左右声道和内部对照一致、声部状态与零输出。A4先用Hann窗FFT寻找80–2000 Hz主峰，再在原始时域样本上最小化正弦/余弦/DC的最小二乘残差，频率误差上限1 Hz。32768点的FFT原始频点间隔约1.4305 Hz，细化估计并未增加原始频谱分辨率。四音用同时拟合四个预期基频的方法降低短窗口泄漏影响：保留音幅值至少1000 LSB，松开音幅值低于100 LSB且低于四音时的1%；同时保留频谱图作复核。

分析器的合成数据自检包含一个正常样例，以及错误采样率、声道损坏、A4偏移3 Hz、缺少一个发声音符、松键后仍保留该音、M0非零、缺帧和立即切断释音八个反例。反例必须被拒绝；合成自检不能代替实际RTL捕获。

## 复现

使用Windows PowerShell 5.1。Icarus路径可通过参数更换；Python只在电脑上离线分析。已有NumPy/Matplotlib时复用对应Python；否则在项目目录建立独立运行时，不改系统Python。

```powershell
python -m venv tools/.venv-audio-analysis
& tools/.venv-audio-analysis/Scripts/python.exe -m pip install -r tools/audio_capture/requirements.txt
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run_audio_verification.ps1 `
  -OutputDir tmp/S1-check-20261014 `
  -Iverilog C:/iverilog/bin/iverilog.exe -Vvp C:/iverilog/bin/vvp.exe
if ($LASTEXITCODE -ne 0) { throw 'S1 verification failed' }
```

输出目录应使用新路径，脚本拒绝覆盖已有门禁日志。输出包括生产与测试输入的SHA256、Git基线及工作区状态、工具路径/版本、完整门禁日志、CSV及manifest、分析器反例日志、逐段16位双声道PCM/WAV、频谱/释音PNG和JSON指标。`build/`中的`.vvp`属于可清理的编译中间产物，其余是复现及验收证据。`tools/.venv-audio-analysis`是保留的工具运行时，不进入Git，不当临时目录清理。

仅运行RTL门禁时使用原`sim/run_simulation.ps1`。新增可选参数`-AudioCaptureDir`指定CSV输出位置、`-BuildDir`指定编译产物位置；默认CSV写入工作区`tmp/audio_capture`，编译位置仍兼容原脚本。普通RTL门禁包含串行和时序断言；完整S1结论还需要上面的协调脚本执行Python频谱/格式验收。

## 数据和依赖

CSV列为`frame,left,right,stage,gate_mask,idle_mask,note0,note1,note2,note3,final_sample_reference`。最后一列是左字起始时保存的发送器`frame_data`，名称沿用“最终发送样本参考”，不能理解为读文件时的实时`final_sample`。`frame`为从解码器启动开始的完整帧序号；各段之间允许有未保存的稳定等待帧，段内必须连续。`capture_manifest.csv`为key/value格式，记录采样率、时序、段长、预期音符及测试完成标记。未写入PASS尾项的中断捕获不能验收。

离线库固定为NumPy 2.3.5（BSD-3-Clause）、Matplotlib 3.10.8（其项目许可证）。完整传递依赖由pip安装，运行环境版本另记入证据。FFT与线性最小二乘使用[NumPy rfft](https://numpy.org/doc/stable/reference/generated/numpy.fft.rfft.html)和[lstsq](https://numpy.org/doc/stable/reference/generated/numpy.linalg.lstsq.html)。参考了[nishadsuresh/fpga-verilog-synth](https://github.com/nishadsuresh/fpga-verilog-synth)的RTL捕获→PCM/WAV→FFT组织思路；该项目为MIT，只借鉴验证流程，没有复制源码或引入其单声部顶层。

这些检查覆盖四声部数字音频路径的行为，不测量模拟底噪、DAC/耳放电气指标、实物晶振偏差或整机触键到声音延迟。S1 初次交付未修改生产 RTL；S2 的 GPIO、顶层和引脚变化另见 [S2 复核记录](../../evidence/2026/10/FPGA-S2-复核-20261014-v0.1.md)，其资源以对应 PnR 报告为准。已烧录生产位流的状态与当前工作分支分开记录。
