# S5 压力滤波与持续弯音数字交付

`pressure_bend.v` 在 `control_tick`（目标 2 kHz）采样 FSR/电位器：压力先
经过三点中值，再按有符号 `y += (median-y) >>> 1` 的定点 IIR 更新；递推本身
固守在 0..4095，代码里的显式钳位是防御性写法（参考实现以不钳位方式重算
整条向量，越界次数为 0）。`pressure_enable=0` 只旁路表情输出，滤波状态仍
更新。

弯音以 ADC 中点 2048 为零，两个半程都按“幅值向下截断”的整数除法映射到
±2 个半音（Q8 的 ±512，分母由 `ADC_CENTER` 推导，含零值守护），再以五个
固定 Q16 半音锚点分段线性插值，改变 `phase_inc_out`。压力值不参与相位增量，
因而持音时压力变化不会重启 ADSR 或改变音高。相位乘法显式加宽两个操作数，
不依赖工具对乘积宽度的上下文推断。五个锚点是 2^(n/12) 的近似：-2 半音
+0.417 音分、-1 半音 +0.007 音分、0 音分、+1 半音 -0.772 音分、+2 半音
-0.746 音分，全范围偏差不超过 0.8 音分；`source/tools/pressure_bend_ref.py`
会把每个锚点的偏差与精确值一并报出。

参考实现 `source/tools/pressure_bend_ref.py` 与 RTL 使用同一套整数运算，并且
可以生成 HDL 逐值对照所需的向量。自检台 `source/sim/tb_pressure_bend.v`
回放 `source/sim/vectors/` 中的向量：640 个压力 tick（零、满幅上/下阶跃、
128 拍斜坡、中值静止、孤立尖峰、固定种子伪随机）与 4096 个弯音 ADC 码的
Q8、Q16 比率、相位增量全部与参考逐值相等，另外核对 90% 阶跃响应（第 5 个
控制 tick，2 kHz 下约 2.5 ms）、弯音边界与中位回正、多基频相位对照、压力
扫描音高不变、压力关闭仍可演奏、持音弯音不重触发 ADSR，并带 200 ms 超时保护。
运行：

```powershell
$env:PATH = 'D:\NanjingUniversity\FPGA\msys64\ucrt64\bin;' + $env:PATH   # 否则会缺少 msys DLL
Set-Location output/handoff_milestone2_20261008/source
python tools/pressure_bend_ref.py --self-test
python tools/pressure_bend_ref.py --vectors sim/vectors      # 改参考后必须重生成
iverilog -g2012 -I . -o sim/tb_pressure_bend.vvp `
  sim/tb_pressure_bend.v rtl/audio/pressure_bend.v rtl/audio/adsr.v
vvp sim/tb_pressure_bend.vvp
# PASS tb_pressure_bend: 640 pressure ticks and 4096 ADC codes match the reference, t90=5 control ticks
```

2026-10-15 的独立复核发现交付版参考在弯音负半程按“负值向下取整”计算，
与 RTL 的无符号整除差一个 Q8 LSB，4096 个码中有 1536 个不符；交付版自检
只采样 0、2048、4095 三个弯音点，恰好落在两者重合处所以没有暴露。同一轮
复核补齐了清单要求的逐值对照、修正参考取整方向、参数化半程分母、显式加宽
相位乘法并订正锚点注释，门禁现在包含 14 台，详见
[S5 复核记录](../s5-review-20261015/README.md)。

FSR 是相对表情控制；ADC 读到 0 或满量程不能单独判定断线。压力传感器安装、
ADC 参考电压、弯音旋钮机械范围和真实音高/包络延迟仍属于硬件到货后的 T04
验收。本模块尚未单独做综合与 PnR，`BEND_POS_DEN` 常量除法与 32x17 相位乘法
是资源热点，建议在下一次综合报告中记录占用。