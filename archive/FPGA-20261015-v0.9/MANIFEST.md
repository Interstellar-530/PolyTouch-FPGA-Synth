# FPGA-20261015-v0.9 归档清单

## 内容

本次归档是 2026-10-15 对 S5（压力滤波与持续弯音）数字交付的独立复核与其后的
修正。来源工作树为 `PolyTouch-FPGA-Synth-sim-main-55528`（分支
`fix/m2-build-issues`），交付目录为 `output/handoff_milestone2_20261008/source`。
版本号按 S2 的 v0.4、S3 的 v0.7、S4 复核的 v0.8 顺延取 v0.9；若主工作区流水号
不同只需改目录名。

复核结论：交付版压力侧的定点实现正确，弯音侧存在必须修正的问题。交付版
`pressure_bend_ref.py` 在负半程按“负值向下取整”算，而 RTL 的无符号整除按
“幅值向下截断”，4096 个 ADC 码中有 1536 个码在 Q8、Q16 比率、相位增量三类
比较上不一致；交付版自检只采样 0、2048、4095 三个弯音点，恰好落在两者重合
处，所以没有暴露。清单要求的“0-4095 逐值对照”在交付版里没有实现。此外相位
乘法未显式加宽操作数（依赖工具对乘积宽度的上下文推断），比例锚点注释与数值
不符（+1/+2 半音偏低约 0.77/0.75 音分）。本轮统一取整方向、参数化半程分母、
显式加宽乘法、订正注释，并补齐 640 个压力 tick 与 4096 个弯音码的逐值对照，
14 台门禁退出 0。详细判定与证据见 `evidence/README.md`。

## 目录

- `source/rtl/audio/pressure_bend.v`：修正后的控制模块（分母由 ADC_CENTER 推导并带零值守护、相位乘法显式加宽、注释订正）。
- `source/tools/pressure_bend_ref.py`：定点参考，新增向量生成与锚点偏差报告，取整方向与 RTL 一致。
- `source/sim/tb_pressure_bend.v`：向量回放自检（640 压力 tick + 4096 弯音码逐值对照、多基频相位、压力扫描、压力关闭仍可演奏、持音不重启、t90、超时保护）。
- `source/sim/vectors/`：向量与 `meta.json`（含每支向量的 SHA256 与锚点偏差）。
- `source/sim/run_simulation.ps1`：门禁脚本（14 台）。
- `evidence/README.md`：S5 复核记录。
- `evidence/baseline/`：交付版基线（`pressure_bend.v`、`pressure_bend_ref.py` 取自交付会话写入记录；`tb_pressure_bend.delivery-rev-5973.v` 为交付会话修订，最终修订差异见记录“基线说明”一节；`s5-pressure-bend.md` 为交付说明原件）。
- `evidence/logs/`：修正后通过日志与两项故障注入摘录（逻辑右移 613 条失败、交付版参考取整 4608 条失败）。
- `evidence/gate-20261015.log`：14 台门禁完整输出。
- `FPGA-缺件期间仿真与算法任务-20261014-v0.2-S5复核后.md`：任务清单在本次复核后的副本。

## 复现命令

```powershell
$env:PATH = 'D:\NanjingUniversity\FPGA\msys64\ucrt64\bin;' + $env:PATH
Set-Location output/handoff_milestone2_20261008/source
python tools/pressure_bend_ref.py --self-test
python tools/pressure_bend_ref.py --vectors sim/vectors
pwsh -NoProfile -File sim/run_simulation.ps1 `
  -Iverilog D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\iverilog.exe `
  -Vvp D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\vvp.exe
```

## 回退

`rtl/audio/pressure_bend.v` 用 `evidence/baseline/pressure_bend.v` 覆盖，
`tools/pressure_bend_ref.py` 用同名基线覆盖，`sim/tb_pressure_bend.v` 用
`evidence/baseline/tb_pressure_bend.delivery-rev-5973.v` 覆盖（并删除
`sim/vectors/`）即可回到交付版。

## 限制

只声明 RTL/参考层面的 PASS。未做综合与 PnR：`BEND_POS_DEN` 常量除法与
32x17 相位乘法是资源热点，建议在下一次综合报告里记录占用；把 `/2047` 简化
成 `(x*1025)>>12` 之类的乘法并非等价（2048 个取值里 255 个不符），替换前
必须全量对照。FSR/电位器机械范围、ADC 参考电压、真实音高与包络延迟仍属
T04 实机验收。