# 2026-10-12 修复版 SRAM 板上验证

基线为 Git 提交 `122df4bd1b0660fd5101c92a476a6aeefc93e702`，码流 SHA256 为 `33CC15DC6F75358FB8AB2D0F1879612328F15535249AC136B37E6D9C71D3DD9C`。板卡是 Tang Primer 20K Dock 3714，通过 Dock USB-JTAG Type-C 连接。此次只配置 GW2A-18C 的 SRAM，未写入 Flash。

烧录前运行 `source/sim/run_simulation.ps1`，六个测试台全部 `PASS`，门禁退出码 0。JTAG 只读扫描得到器件 ID `0x0000081B`，旧 User Code `0x000059D1`。Gowin Programmer V1.9.11.03 以 `--operation_index 2` 和 `USB Debugger A/0/9025` 执行 `SRAM Program`，进度达到 100%，打印 `Finished`。烧录后复查得到器件 ID `0x0000081B`、User Code `0x0000FCF0`、Status Code `0x00006020`。

COM13 以 115200 8N1 测试，`N69`、`O69`、`X`、`M0`、`M1` 均得到 `OK` 应答。最后一条 `M1` 解除静音，串口已关闭。这证明修复码流已装载、UART 命令链路可用；耳机实际听感、LED 状态和 ADSR 模拟释放曲线尚未现场观察或测量，不能只凭串口应答判定板级音频验收完成。

本轮只新增验证记录，未修改 RTL、约束或接口。需要回退时，断电重启可重新加载原 Flash 程序。仿真产生的六个 `tb_*.vvp` 中间文件已按明确路径清理，先前的 `_probe.vvp` 未触碰。本地完整归档在 `archive/FPGA-20261012-v0.4/`，含源码、已烧录码流、复现命令、证据、变更说明、MANIFEST 和 SHA256 清单。下一步请在耳机端听测起音、松键与重按，必要时采集 PT8211 输出确认释放包络。
