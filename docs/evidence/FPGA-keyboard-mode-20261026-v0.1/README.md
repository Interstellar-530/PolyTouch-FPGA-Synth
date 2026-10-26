# F7 模式切换自检证据

before/ 保存新增自检在旧 RTL 上的预期失败：F7 did not enter manual mode。targeted/ 保存实现后的 tb_top_host_ctrl，通过，耗时 73.30 秒；该台使用 standard27 音频路径，测试曲单位缩短，串口保持真实 115200。

regression/ 保存原键位、长按、UART D0/D1、旧 GPIO 路径的四项补充自检。完整通过状态及输入 SHA256 以各 gate-result.json 为准。没有修改硬件配置、重建或烧录。本轮没有执行 Full 历史回归或模拟音频实测。

共享工作区曲目在初次测试结束后发生其他修改。snapshot.json 记录冻结方式：b15ff7c 加本次四文件覆盖；frozen/ 是该快照中五项联合复验的最终证据。targeted/ 与 regression/ 仅保留开发过程，不能代替 frozen 的源码绑定。其他工作区曲目文件未覆盖或回退。

设计说明见 docs/releases/FPGA-键盘演奏模式切换-20261026-v0.1.md。修改前快照和最终源码在 archive/FPGA-20261026-v0.3；临时仿真构建结束后清理，测试日志保留。
