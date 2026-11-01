# v1.0.0 外部 Flash 写入与冷启动验收

2026-10-14 按用户要求将昨天发布的 v1.0.0 原位流写入 Tang Primer 20K Dock 的外部 Flash。生产 RTL 没有改变，目标为 GW2A-18C；写入文件是 `releases/2026/10/FPGA-20261013-v0.1/target/instrument_sram_0x5633.fs`，SHA256 为 `2C7C7001DD3EABF24D2A4ABC2FC93BE1DD441D76812E248B3B84A235DBD22675`。烧录前完整重新编译、运行原九项门禁，全部 PASS，绑定 Git 提交 `df66250ad5a449a310779da158bea11bbf0d8916`。本轮之后另开展 S1 测试工程，不改变已写入的逻辑。

当次扫描为 `USB Debugger A/0/9025`，FPGA ID 为 `0x0000081B`，烧录前 User Code 为旧 Flash 的 `0xFCF0`。CIM 串口查询漏报 COM13，`SerialPort.GetPortNames()` 和 PnP 仍确认 `USB Serial Port (COM13)` 正常；因此不把 CIM 的列表当作唯一连接依据。

先执行操作9 `exFlash Erase,Program,Verify`，地址0、JTAG 2.5 MHz。写入/校验达到100%后仍出现 `Error: SPI Verify failed!`，进程退出码却为0，与10/12历史异常一致。这次操作没有通过校验，完整日志保留。随后改用操作37 `exFlash Erase,Program,Verify thru GAO-Bridge`，同一文件/地址/频率，明确报告 `Program and Verify flash successfully.`，退出码0，日志无 Error。这是本次采用的通过路径。[Sipeed 官方常见问题](https://wiki.sipeed.com/hardware/zh/tang/common-doc/questions.html)说明 GW2A 的外部 Flash/Generic Flash/GAO-Bridge 流程；具体操作编号以本机 CLI `--help` 为准。

操作1 `Reprogram` 未传位流，仅从 Flash 重载。紧接着的读取曾得到 User Code 0、Status `0x4460`，首条串口命令超时；延后复读得到 `0x5633/0x6020`，随后 `D0/N69/O69/D1/M1` 均返回 OK。启动就绪应等待 Done，不能把刚结束的 Reprogram 当作应用已就绪；本次没有为这段启动等待再次擦写。

关闭编程器和串口后，请用户断开全部电源约5秒再接回，用户反馈“正常”。冷启动后再次只读确认 User Code `0x5633`、Status `0x6020`，确认新版从 Flash 上电启动。冷启动后的串口复测因 COM13 被电脑演奏窗口占用而未执行，不关闭用户窗口；串口模式命令的通过证据来自前述 Flash 重载后的检查。

归档在 `archive/FPGA-20261014-v0.1/evidence/`：烧录前九台日志及工具版本、位流校验值、扫描与旧码、操作9失败日志、操作37成功日志、重载与延后设备代码、串口检查、冷启动读码及用户验收 JSON。完整 Flash 校验通过和冷启动通过均有证据；普通操作9为何读回失败仍未定位，今后优先使用已通过的 GAO-Bridge 路径。

回退需要主动重写已知旧位流 `archive/FPGA-20261012-v0.5/deliverables/lanhuacao_adsr_fixed.fs`，SHA256 `33CC15DC6F75358FB8AB2D0F1879612328F15535249AC136B37E6D9C71D3DD9C`，并在操作前通过适用的完整门禁。断电将启动本次新版，不会恢复旧 Flash。
