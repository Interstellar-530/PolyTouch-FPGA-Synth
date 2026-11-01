# 2026-10-26：周末版本写入外部 Flash

用户要求“首先将周末版本的代码烧录到flash内”，随后明确要求“跳过门禁”。本轮选取周末最后归档的 FPGA-20261024-v0.4：standard27 / IdleOnly，CH9350L 输入、外接 PCM5102A、FSR 按住消音与旋钮弯音。没有修改 RTL 或重新构建，本轮没有运行仿真。原历史 Quick 19 项和四项定向测试结果保留，不能表述成本轮重新通过。

烧录前识别 USB Debugger A 通道 0，位置 561；FPGA GW2A-18C，ID 0x0000081B，User Code 0x00003F62、Status 0x00006020。对原归档构建收据的 193 个输入逐一核对 SHA256；目标位流 SHA256 为 e9341aa47674ecf90bf677024830f4de7a771e3b56384240b9c32382cc062137。

使用 Gowin Programmer V1.9.11.03 Education、本机操作 37 `exFlash Erase,Program,Verify thru GAO-Bridge`，2.5MHz、默认地址 0，执行项目 program_sram.ps1 的显式 -FsFile、-Operation 37、-SkipSimulation 路径。该脚本名含 sram，但本次实际操作为日志确认的外部 Flash 擦写校验。烧录器耗时 27.25 秒，明确输出 `Program and Verify flash successfully.` 与 `Finished.`，退出码 0，日志无 Error。

操作 1 `Reprogram` 未传位流，从 Flash 重载。首次 2 秒后读码仍是 User Code 0、Status 0x00004460；未重新擦写，延后只读检查得到 User Code 0x000063DC、Status 0x00006020。Flash 写入校验和 Flash 重载标识检查已通过。没有操作 USB 电源或做彻底断电冷启动，没有发送串口预设或进行音频、FSR、键盘验收。

操作依据为本机 CLI --help、此前本板操作 37 成功记录及 [Sipeed 外部 Flash / GAO-Bridge 说明](https://wiki.sipeed.com/hardware/zh/tang/common-doc/questions.html)。没有使用本板历史上曾报 SPI Verify failed 的普通操作 9。

归档 archive/FPGA-20261026-v0.1 包含源码、目标位流、已知旧版回退位流、原历史验证、本次原始日志、复现脚本、MANIFEST 和 SHA256。证据入口 evidence/2026/10/FPGA-weekend-flash-20261026-v0.1。本轮没有生成临时构建或仿真目录；复制源码若含 Python 缓存则按明确路径清理并记录，运行依赖保留。下一步可断开全部供电后重新上电检查冷启动，并按接线表继续连接 CH9350L。
