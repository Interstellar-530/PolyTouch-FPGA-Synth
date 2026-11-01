# CH9350L 代码核对证据

审核说明见 docs/reviews/FPGA-CH9350L代码核对-20261026-v0.1.md。本轮只审核和验证，没有修改生产 RTL、构建位流或操作板卡。

host/：三项键盘链路测试全部通过，56.92 秒。quick/：十三正例与六参数负例全部通过，63.83 秒；其中已经包括 Host 的三项。song/：曲目时序及背压两项通过。各目录 gate-result.json 保存选中清单、退出码、输入 SHA256、测试耗时和本轮没有检测到输入变化的记录。ChangedDuringRun 的 [null] 是 PowerShell 空集合序列化，不是一个文件变化。

flashed-source-comparison.json 记录七个 CH9350L 关键文件与已写 Flash 归档完全一致。本轮的当前曲目源码比 Flash 归档多三处修改，未重新构建或烧录。实际硬件兼容与持键无通知断电行为仍待现场验收。

复现：在仓库根运行 source/sim/run_simulation.ps1（完整前缀 output/handoff_milestone2_20261008/），-Suite Host 运行三项，默认运行 Quick；曲目使用 -Tests @('tb_song_timing','tb_song_backpressure')。运行环境为已有 C:\iverilog 和 PowerShell。
