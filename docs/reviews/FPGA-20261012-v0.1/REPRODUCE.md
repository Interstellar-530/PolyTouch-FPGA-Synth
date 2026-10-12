# 复现与核对

在仓库根目录运行原 RTL 仿真门禁：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'output/handoff_milestone2_20261008/source/sim/run_simulation.ps1'
```

当前基线的额外 ADSR 回归预期返回非零，并显示松键 2000 个采样节拍后 `env=45875`、`idle=0`。`iverilog` 和 `vvp` 由本机 Icarus Verilog 提供；路径按实际安装位置调整。

```powershell
New-Item -ItemType Directory -Path 'tmp/adsr_review' -Force | Out-Null
& 'C:/iverilog/bin/iverilog.exe' -g2012 -s tb_adsr_release_audit -o 'tmp/adsr_review/adsr.vvp' 'output/handoff_milestone2_20261008/source/rtl/audio/adsr.v' 'docs/reviews/FPGA-20261012-v0.1/tb_adsr_release_audit.v'
& 'C:/iverilog/bin/vvp.exe' 'tmp/adsr_review/adsr.vvp'
```

表格用 Python 和 `openpyxl` 复开验证：

```powershell
python 'docs/reviews/FPGA-20261012-v0.1/verify_workbook.py'
```

`peripherals.json` 保存表格原始行与来源，工作簿可直接在 Excel 编辑。原工作簿构建脚本保留在本地完整归档中，使用 Codex bundled `@oai/artifact-tool`；它不是本仓库的生产依赖。PnR 数字可在 `instrument.rpt.txt` 的 Resource Usage Summary 复查；这份报告的基线是 Git 提交 `2c3846c49c75d701bde2352b84cfa3a36316abbb`。任一生产 Verilog 修复都必须先补测试并使全门禁通过，再运行布局布线或烧录。

以上命令不修改板上配置。仿真命令生成的文件只位于指定 `tmp/adsr_review` 目录，复查结束后可按项目清理规则删除。
