# 2026-10-30 快速延音踏板 SRAM 下载

用户要求“烧录”“直接烧”。沿用archive/FPGA-20261030-v0.6已通过的7项定向RTL自检与1项真实生产顶层自检，核对384项顶层仿真输入SHA256一致后，不重跑门禁，使用既有hdmi构建入口重新实现。未修改生产源码、约束、配置或门禁脚本。program_sram.ps1尚不支持hdmi档，因此直接使用项目原生Programmer操作2下载已经仿真并实现通过的位流，没有使用SkipSimulation。

Gowin实现完成，Setup/Hold违例端点均为0，BSRAM31/46、MULT18X18为5。计算域54MHz约束下Fmax54.879MHz，最差setup余量0.297ns。位流SHA256为b4dd1b5d1a5d89ba871e34f4e230a85fbe3c92c486934f57dcc811bdb2edf003。

下载SRAM达到100%、Finished、退出0；独立读码ID0x0000081B、User Code0x00002626、Status0x00006020，退出0。原User Code为0x0000F6E3。Flash未写，断电后恢复此前Flash版本。实物响应与听感仍待现场确认。

归档archive/FPGA-20261030-v0.7，包含源码、位流、复现命令、构建/时序/仿真复用与下载证据、MANIFEST及SHA256。没有本轮临时目录待清理，成功构建目录因收据引用保留。
