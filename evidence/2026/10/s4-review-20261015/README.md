# S4 MCP3208 数字交付独立复核（2026-10-15）

本记录复核 `output/handoff_milestone2_20261008/source` 中 S4 的三件交付物：`rtl/audio/mcp3208_spi.v`、`sim/mcp3208_model.v`、`sim/tb_mcp3208_spi.v`（交付时间 2026-10-14 22:13～22:49，交付说明见 `../s4-mcp3208.md`）。复核依据是 Microchip MCP3204/3208 数据手册 DS21298E 的第 5.0 节串行通信说明、Table 5-2、Figure 6-1 与第 4 页时序参数，摘录见 `datasheet-excerpt.txt`。工具为本机 MSYS2 UCRT64 的 Icarus Verilog 13.0（`D:\NanjingUniversity\FPGA\msys64\ucrt64\bin`），日志在 `logs/`，整包门禁日志在 `gate-20261015.log`。交付版三件文件的原样副本与校验值在 `baseline/`。

## 结论

交付版的帧对齐错开一个时钟，并且整帧少一个时钟：它只发 18 拍 SCLK，在第 7～18 个上升沿采样 12 位，而 DS21298E 规定起始位之后的第 7 拍是器件驱动、主机锁存的 null 位，数据位 B11～B0 落在第 8～19 拍。按交付版实现，器件返回的真实码会被整体右移一位，B11 位置被 null 位的 0 顶替，B0 完全丢失；满量程 4095 会读成 2047，任何非零输入都近似减半。这正好命中任务清单在 S4 自检标准里写明的“无错位串值”一项，因此 S4 不能按交付版验收。本轮已按数据手册修正主机与器件模型，并把自检改写为与手册时序对照的独立审计，14 台门禁全部通过。

交付版自检必然通过的原因在于自证式建模：`mcp3208_model.v` 把 B11 排在第 7 个上升沿摆上 MISO，与主机第 7～18 拍采样窗口共享同一错误假设，两者互相印证，测试台无法发现对齐问题。原交付说明中“检查了 null 位不会错位串值”一句因此不成立。

## 判定依据

DS21298E 第 5.0 节写明：CS 拉低后第一个 DIN 为高的时钟构成起始位，随后是 SGL/DIFF 与 D2、D1、D0；D0 之后“还需要一个时钟完成采样保持（该时钟 DIN 无关）”，器件在随后那个时钟的下降沿开始输出低电平 null 位，再之后的 12 个时钟以 MSB 先出输出转换结果，数据始终在时钟下降沿输出、由主机在上升沿锁存。起始位之后的第 7 拍是 null 位，第 8 拍是 B11，第 19 拍是 B0，所以一次完整的 MSB 先出读需要 19 个 SCLK 脉冲。

Figure 6-1 用带编号的 24 拍字节化传输示例给出了同一结论：前 8 拍对应 8 个未知位，第二字节的组成是“3 个未知位、null 位、B11～B8”，第三字节是“B7～B0”；图注同时明确“MSB 在编号 12 的时钟下降沿移出”。该示例的首字节含 5 个前导零，起始位落在第 6 拍，于是 null 位锁存在第 12 拍、即起始位之后的第 7 拍，B11 在第 13 拍，与前一段完全一致。Table 5-2 确认单端模式下 SGL/DIFF=1、D2 D1 D0 即通道号二进制，交付版的命令位顺序正确，问题只出现在读回窗口与帧长。

## 证据

按数据手册重写的器件模型 `sim/mcp3208_model.v` 与原交付 RTL 对跑，得到 14214 条失败、退出码 1，失败形态统计与首尾摘录在 `logs/pre-fix-vs-datasheet-model.excerpt.log`：282 次“帧只用 18 拍 SCLK / 18 个器件时钟，期望 19”，280 次数值错误，例如 `value=3800` 读回 `1900`、`value=2049` 读回 `1024`（即右移一位），另有 13650 次“CS 仍为低就更新了 data”，说明交付版 RTL 在最后一个数据位的上升沿写 `data`，与交付说明所称“完成最后一个下降沿后才把 data 更新”不符。

修正版（19 拍、在第 8～19 拍采样、在整帧最后一个下降沿提交）与同一手册模型对跑通过，日志 `logs/post-fix-tb_mcp3208_spi.log`。新增的两台测试同样通过：`logs/post-fix-tb_mcp3208_i2s_coexist.log` 记录 40 次 ADC 事务期间 PT8211 的 169 个 tick 间隔全部严格 576 拍、1440 个 SCLK 半周期全部严格 54 拍；`logs/post-fix-tb_mcp3208_params.log` 记录 27 MHz/250 kHz 生产参数下 19 个上升沿、半周期 54 拍、CS 到首个上升沿 2000 ns（满足 tSUCS ≥ 100 ns），SPI_HZ 高于 CLK_HZ/2 时钳位成一拍仍能完成事务，SPI_HZ=0 的实例可以正常综合出网表且保持空闲。完整门禁 `gate-20261015.log` 覆盖 14 台测试并输出“全部测试台通过，允许烧录”，退出码 0。波形证据见 `mcp3208-frame-20261015.png`：它由 `tools/render_mcp3208_waveform.py` 从 `+dump` 生成的 VCD 渲染第 11 次事务，渲染器自身校验该帧为 19 拍、DIN 第 1/2 拍为 START 与 SGL/DIFF、通道位译码为 0、MISO 第 8～19 拍译出 0x55E=1374，与器件随后提交的保持值一致，退出码 0。

## 修改内容

| 文件 | 修改 | 依据 | 回退 |
| --- | --- | --- | --- |
| `rtl/audio/mcp3208_spi.v` | 帧长 18→19 拍；采样窗口改为 `bit_index` 7～18（第 8～19 拍）；`data` 改为整帧最后一个下降沿与 `done` 同拍提交；增加 `SPI_HZ < 1` 的守护 localparam | DS21298E §5.0、Figure 6-1 | 用 `baseline/mcp3208_spi.v` 覆盖 |
| `sim/mcp3208_model.v` | 按手册重写 MISO 时序：忽略起始位之前的前导零，第 7 拍给 null 位，第 8～19 拍给 B11～B0 | DS21298E §5.0、Figure 6-1 | 用 `baseline/mcp3208_model.v` 覆盖 |
| `sim/tb_mcp3208_spi.v` | 重写自检：线级审计（帧长、DIN 命令位与通道译码、CS 低期间不得提交、每帧一个 done）、8 路互异非零码值、CH0/CH1 双通道交替、0/1/2047/2048/4095 边界码、256 例 xorshift32 固定种子随机通道与码值、busy 期间 start 忽略、帧内第 3/8/15 拍复位恢复、200 ms 超时保护 | 任务清单 S4 自检标准 | 用 `baseline/tb_mcp3208_spi.v` 覆盖 |
| `sim/tb_mcp3208_i2s_coexist.v`（新增） | 生产参数下 ADC 事务与 PT8211 音频并行，检查 tick 严格 576 拍、SCLK 半周期严格 54 拍、每帧码值正确 | 任务清单 S4“ADC 不阻塞 I2S” | 删除文件并从 `run_simulation.ps1` 队列移除 |
| `sim/tb_mcp3208_params.v`（新增） | 27 MHz/250 kHz、过高 SPI_HZ 钳位、SPI_HZ=0 三类参数边界 | S3 复核沿用“参数负例”做法 | 同上 |
| `sim/run_simulation.ps1` | 队列由 12 台扩到 14 台并更新表头说明 | 新测试需要进门禁 | 回退表头注释与两个数组项 |
| `sim/tb_mcp3208_spi.v`、`sim/tb_mcp3208_i2s_coexist.v` | 波形转储改为只在 `vvp … +dump` 时写 VCD，门禁不再在源码目录留下二十余 MB 的 `.vcd`；同时删除交付版遗留的 `tb_mcp3208_spi.vcd` 与已失真的 `tb_mcp3208_spi_waveform.png` | 项目规则要求临时产物可复现且不留在源码树 | 恢复 `\`/`\` 原位置 |
| `tools/render_mcp3208_waveform.py`（新增） | 从 VCD 渲染单帧波形，并自检帧长、DIN 命令位与 MISO 第 8～19 拍译码等于提交值 | 复核结论需要可查看的波形证据 | 删除文件即可，不影响 RTL |

## 对照任务清单 S4 自检标准

| 清单要求 | 本轮覆盖方式 |
| --- | --- |
| 独立解析 Start/单端/CH0/CH1/null/12 位数据 | 线级审计逐拍核对起始位、SGL/DIFF、D2～D0 与 19 拍帧长；数据位按数据手册第 8～19 拍对齐 |
| 0/1/2047/2048/4095 和固定种子随机值无错位串值 | CH0 与 CH1 各跑 5 个边界码；256 例 xorshift32 固定种子随机通道与码值 |
| 两通道测试 | 8 路通道同时持有互不相同的非零码值，CH0/CH1 交替读取 4 轮，错通道译码无法蒙混过关 |
| CS 中断/复位可恢复 | 帧内第 3、8、15 拍分别施加复位，检查 CS/SCLK/busy/done 立即回到空闲、无提交，随后事务正常 |
| 完整事务后才提交 | `data` 只在整帧最后一个下降沿更新；审计检查 CS 为低期间 `data` 不变、每帧仅一个 `done/data_valid` |
| ADC 不阻塞 I2S | `tb_mcp3208_i2s_coexist` 在 27 MHz 同源时钟下并行运行，tick 间隔全部严格 576 拍 |

## 未覆盖与风险

本轮仍是数字交付：`mcp3208_spi` 未接入顶层，未改 CST/SDC，未切换系统时钟，实体 ADC 的供电、参考电压、噪声与 FSR 机械特性都要等到货后逐件验收。帧对齐结论来自数据手册，正式上板时应再用逻辑分析仪抓 CS/SCLK/DIN/DOUT，确认第 7 拍为 null 位、第 8～19 拍为 B11～B0。

CS 高电平时间需要调用方保证。器件要求 tCSH ≥ 500 ns，而本模块背靠背事务之间最快只留一个 27 MHz 时钟（约 37 ns），低于手册要求；以 1～2 kHz 调度压力采样时该间隔天然满足，S5 与顶层集成时必须保证请求间隔，或在此模块内补一个最小间隔计数。

`start` 在 `busy` 期间被忽略且不排队，调用方必须等 `busy` 回落再发起下一次请求；若要改成请求锁存会改变接口语义，本轮未做，留给顶层集成时决定。

钳位档（SPI_HZ 高于 CLK_HZ/2）的 CS 建立时间只有约 37 ns，低于 tSUCS ≥ 100 ns，该档只用于参数边界验证，不能作为生产配置使用。

交付说明里“本机 MSYS2 Icarus 驱动在生成 .vvp 后会额外返回 Windows access violation -1073741819”并不准确：沙箱内运行时驱动报 0xC0000005，沙箱外但 PATH 未含 `msys64\ucrt64\bin` 时报 0xC0000135，把该目录加入 PATH 后 `iverilog` 与 `vvp` 均干净退出 0。写入归档与后续脚本时按后者配置即可。

## 复现命令

```powershell
# 完整门禁（14 台），需要把 UCRT64 bin 放进 PATH
$env:PATH = 'D:\NanjingUniversity\FPGA\msys64\ucrt64\bin;' + $env:PATH
pwsh -NoProfile -File output/handoff_milestone2_20261008/source/sim/run_simulation.ps1 `
  -Iverilog D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\iverilog.exe `
  -Vvp D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\vvp.exe

# 单台 S4 自检
Set-Location output/handoff_milestone2_20261008/source
iverilog -g2012 -I . -o sim/tb_mcp3208_spi.vvp sim/tb_mcp3208_spi.v sim/mcp3208_model.v rtl/audio/mcp3208_spi.v
vvp sim/tb_mcp3208_spi.vvp

# 复核交付版错位：用 baseline/mcp3208_spi.v 替换 rtl/audio/mcp3208_spi.v 后重跑
# 上面的单台命令，会得到 exit 1 与“frame used 18 SCLK edges … expected 19”
```