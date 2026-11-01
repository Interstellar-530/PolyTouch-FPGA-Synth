# 使用入口

当前源码位于 `source/`。从仓库根目录运行 `& './source/sim/run_simulation.ps1' -Suite Quick` 执行短门禁；完整历史回归使用 `-Suite Full`。构建运行 `& './source/build/build.ps1' -Profile hdmi`，其他档位见[构建说明](../../source/build/README.md)。

烧录入口是 `source/build/program_sram.ps1`，必须使用新路径下的构建收据并通过仿真。本次整理没有进行烧录，也没有生成新位流。电脑端演奏工具见[串口键盘](../../tools/serial_keyboard/README.md)。硬件接线按[硬件资料](../hardware/)及对应日期版本的验收范围核对。

历史版本需要在独立工作树中按当时的 README 复现，见[版本时间线](../history/VERSIONS.md)。
