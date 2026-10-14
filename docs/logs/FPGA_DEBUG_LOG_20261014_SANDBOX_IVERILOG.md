# 调试记录：Codex Windows 沙箱下 Icarus Verilog 编译崩溃

日期：2026-10-14。触发场景：在 Codex 会话的默认沙箱内运行本项目的 RTL 仿真门禁。

## 现象

在沙箱内运行 `sim/run_simulation.ps1` 时，多台测试台报"编译失败"。单独复现：`iverilog` 编译任意 Verilog 源都返回退出码 `-1073741819`（即 `0xC0000005`，访问越界），但同一次执行会把 `.vvp` 正常写出来，随后 `vvp` 运行该文件结果完全正确（tb_adsr 打印 PASS 且退出码 0）。换到沙箱外执行同样的命令，退出码 0。

其它观察：`iverilog -V`、`iverilog -E`、`ivl.exe -h`、`ivlpp.exe -h`、`vvp`、`cmd`、PowerShell 管道、`git status` 在沙箱内都正常退出；只有真正跑 `ivlpp | ivl` 后端那一步崩。重复 8 次编译，8 次全部返回 `0xC0000005`，是稳定复现而不是偶发竞态。

## 环境事实

`codex doctor` 报告当前后端为 `mxc`。配置 `C:\Users\ROG\.codex\config.toml` 里有 `[windows] sandbox = "elevated"` 与 `[features] prefer_mxc = true`。沙箱内进程的 `LOCALAPPDATA` 与 `TEMP` 被重定向到 `C:\Users\ROG\AppData\Local\Packages\sandbox.{GUID}\AC`，这个路径在真实文件系统上并不存在，说明 mxc 通过注入代理做了路径虚拟化；`C:\iverilog` 目录本身没有 `CodexSandboxUsers` 授权条目，读源文件仍然成功，所以崩溃不是简单的读取被拒。

排除项：把 `TEMP`/`TMP`/`TMPDIR` 指向工作区目录、把 `LOCALAPPDATA`/`APPDATA` 指回真实路径、把 `-o` 输出放到临时目录或工作区，都不改变结果；`-t null` 同样崩溃。因此与临时目录位置无关。

## 备选后端为何没能顶上

把 `prefer_mxc` 关掉后 `codex doctor` 报告后端变成 `elevated`，但同时报 "elevated Windows sandbox provisioning recorded a structured failure / error code helper_unknown_error"。这与 `C:\Users\ROG\.codex\.sandbox\setup_error.json` 的内容一致；最近一次真实预配置日志（`sandbox.2026-10-11.log`）里唯一的结构化错误是：

```
runtime read/execute validation failed: validate runtime read/execute access on
C:\Users\ROG\AppData\Local\OpenAI\Codex\runtimes\cua_node\...\bin\node_repl.exe:
open ACL target for root-only update: 另一个程序正在使用此文件 (os error 32)
```

即预配置在给 `node_repl.exe` 更新 ACL 时被文件占用挡住，整个 setup 刷新失败。所以现在只有 mxc 这条后端可用，而 mxc 恰好会打断 Icarus 的编译退出码。

## 结论与可选处置

同源文件的沙箱内外对照支持“当前沙箱与 Icarus 编译工具存在兼容问题”的判断，具体崩溃位置尚未定位。一次 `vvp` 自检通过只证明该次留下的文件可运行，不能把所有非零编译退出码当作成功。门禁继续保留编译退出码检查。可选的处置按风险从低到高：

1. 门禁在沙箱外执行。本轮已为 `iverilog.exe`、`vvp.exe`、`powershell -NoProfile -ExecutionPolicy Bypass -File` 建立持久放行规则，后续任何模型跑门禁都不再需要逐次确认。这条已经验证可用。
2. 关掉 mxc 走 `elevated` 后端（`[features] prefer_mxc = false`）。前提是先把上面的预配置修好：需要在不占用 `node_repl.exe` 的情况下让应用重跑一次带提权的 sandbox setup，然后重启 Codex。本轮无法验证该后端下 Icarus 是否恢复正常，因此没有直接改这份全局配置。
3. 升级 Codex 桌面端（doctor 提示有 26.1007.9446.0 可用）后复测，看 mxc 是否已修。

本轮没有修改 `config.toml`。屏保和显示器/系统/硬盘的自动关闭超时已按要求关闭（`ScreenSaveActive=0`、`monitor-timeout-ac/standby-timeout-ac/hibernate-timeout-ac/disk-timeout-ac` 均为 0），这一项是全局电源设置，需要时可以改回。

2026-10-14 S2 复核再次用相同 `tb_adsr.v` 和 `adsr.v` 对照：默认沙箱编译退出 `-1073741819`，沙箱外编译退出 0，两者的 `vvp` 自检都退出 0。当前配置仍为 `prefer_mxc = true` 与 `windows.sandbox = "elevated"`。日志保存在 `docs/evidence/FPGA-S2-复核-20261014-v0.1/sandbox_probe.log` 与 `outside_probe.log`。本次只核对配置，没有更改全局设置。
