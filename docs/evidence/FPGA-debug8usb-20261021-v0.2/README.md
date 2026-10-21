# PolyTouch debug8usb GitHub 证据（2026-10-21 v0.2）

本目录保存最新 debug8usb 位流和关键验收证据。完整 216 文件归档位于工作区外部的 D:\NanjingUniversity\FPGA\PolyTouch-FPGA-Synth-20261021-debug8usb-v0.2，其中包含完整 RTL、仿真、工具、约束、构建脚本、复现入口和详细 MANIFEST。

- 源提交：1fd865a3503d988a70943c0788db0e4523dc98ec
- 位流 SHA256：FB8853751564EDA8620906469816E034229194AB874E66620B0147855B4DEFFD
- 完整门禁：64 台正向测试台与 6 个参数负例 PASS，退出码 0。
- 长时捕获：	b_audio_capture PASS，58,880 个原生 PT8211 帧。
- 时序：Setup 最差 +6.967 ns，Hold 最差 +0.317 ns，均为 0 条负裕量。
- 缺失并明确跳过：	b_piano_engine、	b_piano_morph、	b_piano_envelope、	b_top_i2s_27m、	b_generic_bright。

尚未进行实体板卡烧录、普通 USB 键盘/CH9350L 链路和 FSR 标定验证。详细配置、风险和复现命令见 MANIFEST.md、gate_summary.txt 及字节流回执。