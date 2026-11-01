# 2026-10-13 串口窗口输入设置与收尾

此前 PuTTY 能连接 COM13，但板上协议不逐字回显，默认本地回显关闭时看不到输入。2026-10-12 已在当前窗口开启 Local echo 和 Local line editing 的 Force on，用户确认“能看到 D1 和 OK”。本轮完成这组设置的持久化、启动验证及归档。

`tools/putty/configure-session.ps1` 建立或更新专用 `PolyTouch-COM13` 会话：串口为 COM13、115200、8N1、无流控，本地回显和行编辑均启用。PuTTY 对这两个三态设置的存储值 0 表示 Force on。脚本核对全部写入值，现有会话中其他选项保留。`install.ps1` 在安装后执行此脚本，`open-serial.cmd` 通过 `-load PolyTouch-COM13` 打开；启动参数仍明确指定 COM13 和串口格式。

实际重新打开窗口后，读取 Terminal 设置页，两个 Force on 单选按钮均为选中状态；终端已恢复到前台，标题为 COM13 - PuTTY。程序运行时和当前打开的窗口属于保留工具，本次未生成一次性辅助脚本。用户可直接输入命令，按 Enter 发送整行；自动串口脚本运行前需要先关闭该窗口以释放端口。

本轮开始读取到板卡 User Code `0x0000FCF0`，说明板卡已从 Flash 加载前版。重新运行完整 RTL 门禁，九项测试全部 PASS，再将此前 v0.6 已验证的同一位流载入 SRAM。读取到 ID `0x0000081B`、User Code `0x00005633`、Status `0x00006020`；D0、N69、O69、D1 经 Plink 实测均返回 OK，最后恢复演示。位流 SHA256 为 `2C7C7001DD3EABF24D2A4ABC2FC93BE1DD441D76812E248B3B84A235DBD22675`。本轮没有修改 RTL或重写 Flash。

源码、可重建的会话设置快照、位流、命令和证据位于 `archive/FPGA-20261013-v0.1/`，校验记录覆盖全部归档文件。本轮生成的九个仿真可执行文件已清理，保留既有 _probe.vvp、运行时和归档证据。代码回退点为此前提交 `057d78c`；配置可删除专用 PolyTouch-COM13 会话后恢复启动脚本，板卡 SRAM 可通过断电回退到保留的 Flash 固件。

下一步限制仍是新模式仅装入 SRAM：断电重上电会回到 `0xFCF0`，D0/D1 需重新加载模式修复版才可用。此前 Gowin Flash 全量校验异常不属于本轮窗口设置修复，未宣称已解决。

说明来源：[PuTTY Terminal 配置说明](https://the.earth.li/~sgtatham/putty/0.85/htmldoc/Chapter4.html#config-localecho)。
