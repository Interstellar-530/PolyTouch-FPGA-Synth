# 2026-10-24 15:10：standard27 重烧

用户要求重新烧录，并随后明确要求跳过门禁。本次按该要求使用 `-SkipSimulation`，跳过原因已在操作前写入 `skip-simulation-reason.txt`。生产 RTL、192 个构建输入和位流哈希均与此前成功构建一致；没有新增仿真通过记录。

烧录前 JTAG 读到旧 debug8 对应标识 `0x00003F62`；本次操作 2 SRAM Program 退出 0，进度 100%，打印 Finished。烧录后独立 JTAG 读到 `0x0000BF87`，与 standard27 位流一致。未写外部 Flash，因此断电或 S4 重配置仍会恢复旧 Flash 配置。

位流 SHA256：`8f70f54bb4cb95b68aeb41ca8180283ebaa33b21b282d88165867af2239723af`。COM13 的 `M0 X V50 I0 T250 D1 M1` 七条命令全部回复 OK，最终播放演示曲、采样钢琴音色、50% 主音量、解除静音，串口已释放。

用户随后反馈仍完全没有音频，之前描述为低频电噪声。用户已确认 CJMCU 排针已焊牢、杜邦母头接排针。模块 VCC 未接、3.3V 孔供电，背面焊桥未处理；没有测量设备或线路输入音箱/耳放。当前仍通过耳机直接接 LINE OUT 试听。没有实测 I2S 电气波形或 DAC 模拟信号，不能把配置标识、串口 OK 或此前仿真通过当作实物音频通过，也未定位为模块损坏。

下一步需要当前实际接线照片和模块正反面照片，核对供电网络、PMOD 正反面定位、模式脚、焊桥及排针焊点。暂不重复烧录或盲改 VCC 供电。

归档：`archive/FPGA-20261024-v0.3`，包含同一源码快照、实际位流、构建收据及本次证据、SHA256。源码和先前完整验证证据来源为 v0.2；新归档没有宣称本次重新通过门禁。本次未创建仿真临时目录或一次性脚本，无新增临时内容需清理。

本次命令（原生产源码入口）：

```powershell
& '.\output\handoff_milestone2_20261008\source\build\program_sram.ps1' -Profile standard27 -HostTimeoutPolicy IdleOnly -SkipSimulation -Programmer 'E:\Gowin\Gowin_V1.9.11.03_Education_x64\Programmer\bin\programmer_cli.exe'
```

这里的 SkipSimulation 只记录本次用户明确要求，不改变项目后续默认门禁要求。
