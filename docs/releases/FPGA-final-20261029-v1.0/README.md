# 最终版本 v1.0-final-20261029

生产入口source/build/isolated/top_hdmi_build.v，构建命令source/build/build.ps1 -Profile hdmi。32声部、1024x600 HDMI、均衡钢琴、双测试曲丰富编配、振动波形点阵与四窗口保持（约11.444Hz）。完整本地源码及位流归档archive/FPGA-20261029-v0.9；Git保存可复现源码和关键发布记录，不包含大型运行环境、历史试听和临时布局布线产物。

Flash operation37在1MHz写入及内置校验成功，operation1重载成功。本轮按用户要求跳过RTL仿真、试听、独立读回和冷启动测试；“最终版本”表示本次代码冻结，不代表这些未执行的验证已通过。参见CHANGES.md、program-result.json和烧录日志。
