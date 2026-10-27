# 2026-10-26：F7/F8 新版写入 Flash

按用户“烧”的要求，将已推送提交 b656b0d23cc91fbb6c7ff09a23eb7a691f0756f5 的 standard27 / IdleOnly 写入外部 Flash，包含 F7 手动/自动切换与 F8 暂停/继续。沿用用户反复明确的要求，跳过本轮仿真门禁，未运行 Quick/Full；此前 17.52 秒单项检查证据保留，没有把它写成本轮重新运行。其他未提交的曲目修改保留在工作区，没有加入本次位流。

Gowin V1.9.11.03 Education 从独立源码快照构建，目标 GW2A-LV18PG256C8/I7 C。Logic 11357/20736、Register 3684/16173、BSRAM 27/46；DSP 为 MULT18X18、MULT9X9、MULTALU36X18 各一个。建立/保持违例端点均为零，构建输入与生成包装器、位流 SHA256 均由成功收据绑定。

位流 SHA256：62f815784fbcadf5155f0dae3cecf8e0be847e68d9b42cfe11d36453687b71fc；User Code 0x0000C452。烧录前读到 0x000063DC。操作 37 `exFlash Erase,Program,Verify thru GAO-Bridge` 耗时 26.77 秒，明确输出 Program and Verify flash successfully，退出码 0。随后操作 1 不带位流从 Flash 重载，等待启动后首次读码为 0x0000C452、Status 0x00006020，核对通过。没有做彻底断电冷启动或实体键盘/模拟音频验收。

归档 archive/FPGA-20261026-v0.6，包含精确源码、目标位流、原版 0x63DC 回退位流、构建与烧录原始日志、收据、时序报告、复现命令、MANIFEST 和 SHA256。临时源码提取目录已清理；成功构建目录因收据引用而作为实现证据保留，Gowin/Icarus 等运行依赖保留。

上电默认自动演奏。F7 停曲进入手动，再按 F7 从头自动演奏；F8 在自动模式暂停/继续，保留曲目位置。原 FSR 消音和串口静音仍有效。后续现场确认 F7/F8 实际操作，并在彻底断电再上电后检查新版是否正常启动。
