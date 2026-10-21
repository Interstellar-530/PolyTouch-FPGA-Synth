# MANIFEST

- 归档名称：`PolyTouch-FPGA-Synth-20261021-debug8usb-v0.2`
- 构建日期：2026-10-21
- 源提交：`1fd865a3503d988a70943c0788db0e4523dc98ec`
- 构建档位：`debug8usb`
- 顶层：`top_dbg8usb_build`
- 器件：GW2A-LV18PG256C8/I7，版本 C
- Gowin 工具：V1.9.11.03 Education

## 内容

- `instrument.fs`：本次构建生成的 FPGA 位流。
- `source/rtl`：完整 RTL 源文件。
- `source/sim`：完整仿真测试台、模型和向量。
- `source/tools`：生成与辅助脚本。
- `source/constraints`：物理约束和时序约束。
- `source/build`：构建脚本、档位定义和隔离顶层。
- `evidence/gate_full.log`：完整门禁原始日志。
- `evidence/gate_summary.txt`：门禁、资源、时序和跳过项摘要。
- `evidence/audio_capture.csv`：58,880 帧原始音频捕获。
- `evidence/audio_capture_manifest.csv`：捕获配置与阶段统计。
- `evidence/debug8usb.receipt.json`：与位流绑定的构建输入回执。
- `evidence/build_debug8usb.log`：综合、布局布线与位流生成日志。
- `evidence/instrument.rpt.txt` / `.html`：资源与布局布线报告。
- `evidence/instrument.timing_paths`：Setup/Hold 详细路径。
- `evidence/instrument.pin.html`：引脚落点报告。
- `README.md`：配置、结果、验证状态、风险和复现命令。
- `reproduce.ps1`：从本归档 source 目录重跑门禁和构建的入口。
- `checksums.sha256`：除自身外全部归档文件的 SHA256。

## 关键结论

完整门禁为 64 台正向测试台和 6 个参数负例全部 PASS；`tb_audio_capture` 捕获 58,880 帧并通过。位流 SHA256 为 `FB8853751564EDA8620906469816E034229194AB874E66620B0147855B4DEFFD`。构建与时序通过，但未进行实体板卡输入和音频验收。