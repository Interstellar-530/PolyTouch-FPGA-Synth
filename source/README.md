# 当前工程

正式源码由原 `output/handoff_milestone2_20261008/source` 迁移到这里，RTL、ROM 和约束保持原字节。`rtl/` 是音频、输入和显示实现，`sim/` 是自检门禁，`constraints/` 是引脚与时序约束，`build/` 是 Gowin 构建入口，`tools/` 是工程内生成工具。

在仓库根目录运行 `& './source/sim/run_simulation.ps1' -Suite Quick`；构建使用 `& './source/build/build.ps1' -Profile hdmi`。配置说明见[构建说明](build/README.md)，测试说明见[仿真说明](sim/README.md)。

旧路径中的本机 Gowin 输出与收据仍保留，不属于当前源码，也不能作为新路径下的成功构建收据。生成目录 `source/build/gowin_*`、`source/build/receipts` 与 `source/impl` 不入库。历史版本从[时间线](../docs/history/VERSIONS.md)进入。
