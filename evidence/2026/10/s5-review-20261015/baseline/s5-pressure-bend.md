# S5 压力滤波与持续弯音数字交付

`pressure_bend.v` 在 `control_tick`（目标 2 kHz）采样 FSR/电位器：压力先
经过三点中值，再按有符号 `y += (median-y) >>> 1` 的定点 IIR 更新；边界
始终钳在 0..4095。`pressure_enable=0` 只旁路表情输出，滤波状态仍更新。
弯音以 ADC 中点 2048 为零，在 0..4095 映射到 ±2 个半音（Q8 的 ±512），
并以五个固定 Q16 半音比率分段线性插值，改变 `phase_inc_out`。压力值不
参与相位增量，因而持音时压力变化不会重启 ADSR 或改变音高。

参考实现 `source/tools/pressure_bend_ref.py` 与 RTL 使用相同的中值、算术右移、
边界映射和 Q16 插值。自检台 `source/sim/tb_pressure_bend.v` 覆盖阶跃/90%
响应（5 个控制 tick）、单点尖峰、0/2048/4095 弯音边界、压力关闭、持音弯音
不重触发，以及相位增量的单调性。运行：

```powershell
python source/tools/pressure_bend_ref.py --self-test
Set-Location output/handoff_milestone2_20261008/source
iverilog -g2012 -I . -o sim/tb_pressure_bend.vvp `
  sim/tb_pressure_bend.v rtl/audio/pressure_bend.v rtl/audio/adsr.v
vvp sim/tb_pressure_bend.vvp
# PASS tb_pressure_bend: bounded median/IIR, t90=5 control ticks, bend Q8/phase and held ADSR
```

在本机 MSYS2 环境中，Icarus 驱动生成 VVP 后报告 Windows access violation
`-1073741819`；VVP 实际退出码为 0 且自检通过。该驱动异常不代表 RTL
运行失败，正常 Icarus 安装可直接使用上述命令。

这里的 FSR 是相对表情控制；ADC 读到 0 或满量程不能单独判定断线。压力
传感器安装、ADC 参考电压、弯音旋钮机械范围和真实音高/包络延迟仍属于硬件
到货后的 T04 验收。
