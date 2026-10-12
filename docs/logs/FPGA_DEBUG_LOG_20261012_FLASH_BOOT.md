# 2026-10-12 串口工具与 Flash 冷启动验收

本次按用户要求安装串口工具、发送 M0，并把 ADSR 已修复的《兰花草》测程写入外部 SPI Flash。没有修改 RTL。用户实际断电后重新上电，确认“已重新上电，自动播放兰花草”；随后只读取设备代码，User Code 为 `0x0000FCF0`，Status 为 `0x00006020`。掉电后自动进入测程的目标已通过实机验收。

## 串口工具和静音观察

采用官方 PuTTY 0.85 的 Windows x64 独立程序（MIT 许可证，无额外运行库），安装于 `tools/vendor/putty-0.85/`。两个可执行文件的 SHA256 与官方值一致，Authenticode 签名均有效，签名者为 Simon Tatham。该目录属于保留运行时，已被 Git 忽略；`tools/putty/install.ps1` 可重装固定版本，`open-serial.cmd` 打开图形界面，`send-command.ps1` 通过 Plink 发送命令并检查 OK 应答。

连接参数为 COM13、115200、8N1、无流控。写 Flash 前，通过 Plink 发送 M0 收到 OK，用户反馈“噪声基本不变”。该观察发生于旧 Flash 程序运行时，不能当作模拟电路具体故障的定论。它提示后续应优先检查供电、地线、时钟耦合和 Dock 模拟输出链路。冷启动验收后再次发送 M0、M1，均收到 OK；结束时恢复播放，串口和编程器均已关闭。

来源：[PuTTY 官方发布页](https://www.chiark.greenend.org.uk/~sgtatham/putty/releases/0.85.html)、[串口参数文档](https://the.earth.li/~sgtatham/putty/0.85/htmldoc/Chapter3.html#using-cmdline-sercfg)、[许可证](https://www.chiark.greenend.org.uk/~sgtatham/putty/licence.html)。

## 烧录与证据

烧录前完整执行 `output/handoff_milestone2_20261008/source/sim/run_simulation.ps1`，六个测试台全部通过：tb_tick_rate、tb_song_timing、tb_adsr、tb_voice_retrigger、tb_voice_order、tb_poly。烧录的 instrument.fs 包含先前 ADSR、重按和声部窃取修复，其 SHA256 为 `33CC15DC6F75358FB8AB2D0F1879612328F15535249AC136B37E6D9C71D3DD9C`。本次没有重新修改或构建 RTL。

板卡为 Tang Primer 20K Dock，器件 GW2A-18C。当前 USB Debugger A 通道 0、位置 561；每次连接仍需重新扫描。烧录前读取到 User Code `0x000059D1`，说明原 Flash 内仍是此前程序。使用 Gowin Programmer 的操作 9（exFlash Erase,Program,Verify）从地址 0 写入，检测到 Flash ID `0x0B4017`。

**Gowin 全量读回校验存在未解决异常。** 操作 9 在写入和校验进度到达 100% 后报告 `Error: SPI Verify failed!`，但进程退出码却为 0；不能依据退出码宣称校验通过。随后 0.5 MHz 的独立校验同样失败。边界扫描校验在 0.5 MHz 和 15 MHz 下均进展缓慢，在约 3% 时主动终止，没有完成全量校验。以上原始输出均保留。

此后执行 Reprogram，从 Flash 加载而没有传入新的位流，读取到新 User Code `0x0000FCF0`。最终用户拔掉电源再接回，确认自动播放《兰花草》，冷启动后再次读取仍为 `0x0000FCF0`，串口 M0/M1 均返回 OK。由此确认当前测程可从 Flash 冷启动运行；尚不能声称整片 Flash 的逐字节校验已通过。后续若用于比赛交付，应继续定位读回校验异常并补齐完整校验。

## 归档与回退

关键产物归档到 `archive/FPGA-20261012-v0.5/`，包含原工程源文件、串口工具脚本、目标位流、复现命令、测试及烧录证据、MANIFEST 和 SHA256 清单。源工程对应既有修复，归档中的 instrument 源码从 v0.4 复制，位流与此次实际烧录文件一致。

Flash 中旧测程已被本次授权写入替换，未保存旧 Flash 的原始读出镜像。断电不会回退；需要回退时，应选择已知可用的历史位流，经仿真门禁后重新写入。清理本轮生成的六个 tb_*.vvp 仿真产物，保留原有 _probe.vvp、运行时工具及完整验收证据。
