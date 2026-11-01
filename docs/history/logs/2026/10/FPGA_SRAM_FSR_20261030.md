# 2026-10-30 FSR 防抖版 SRAM 下载

用户要求在不改动其他代码的前提下烧录。本轮没有编辑已有生产代码，沿用前一任务的FSR修复及现有HDMI档。与上一份成功HDMI构建收据相比，全部构建输入只有rtl/audio/fsr_mute.v、rtl/instrument32_top.v两项变化，分别是连续样本确认逻辑和32声部实例的2/40样本配置。其余构建输入一致，本轮构建前后输入哈希一致。

使用已有build.ps1 -Profile hdmi生成位流，Gowin V1.9.11.03 Education综合、布局布线完成。资源BSRAM 31/46、MULT18X18 5（另有MULTALU36X18等），时序报告Setup和Hold违例端点均为0。构建目录为source/build/gowin_top_hdmi/runs/20261030T161536900-5c834794。

位流SHA256：4263fa307340a8dbf6e1a4dd66fa7fb384cf03112d7356cc58e662828d70d1e3。下载前检查该哈希及当前源码与成功构建收据一致。

下载使用GW2A-18C、USB Debugger A、cable-index 1、1MHz、operation_index 2（SRAM Program）。进度100%、Finished、进程退出0；工具输出User Code 0x0000ECAE、Status 0x00006020。随后独立运行operation_index 0（Read Device Codes），再次读得ID 0x0000081B、User Code 0x0000ECAE、Status 0x00006020，读码退出0。烧录前User Code为0x0000DADD。已下载SRAM，未写Flash，断电后恢复Flash中旧版本。

仿真沿用前一任务的三项FSR定向通过证据；用户已要求跳过不必要门禁并明确要求烧录，本轮未重跑Quick/Full。前一轮Quick的曲目断言失败与32声部顶层180秒超时仍保留，没有视为通过。由于现有program_sram.ps1不接受hdmi Profile且默认重新执行Quick，本轮直接使用项目已采用的Programmer原生命令执行已授权下载，没有修改脚本来关闭检查。

前置只读操作曾误用编号5，被工具以缺少数据文件拒绝，未进入设备操作；查询帮助确认Read Device Codes为0后完成读码。没有为此次错误发起写入。

归档：archive/FPGA-20261030-v0.3，包含源码快照、目标位流、输入和位流哈希、实现报告、下载及独立读码日志、复现命令与回退说明。成功构建目录因收据引用而保留，无本轮一次性临时脚本或仿真目录待删除；未清理旧任务内容。实物FSR持续按压、松开响应及声音仍需现场确认。
