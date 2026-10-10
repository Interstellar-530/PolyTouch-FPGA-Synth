# FPGA 电子乐器调试日志（2026-10-10 修订三：降噪与按键复位）

## 基本信息

| 项目 | 内容 |
| --- | --- |
| 日期 | 2026-10-10 |
| 板卡 | Sipeed Tang Primer 20K 核心板 + Dock 3714 |
| FPGA | GW2A-LV18PG256C8/I7，器件版本 C |
| 工具 | Gowin Education V1.9.11.03 |

## 一、耳机里的闪烁噪声

### 先排除波表

把 `wave_sine.hex` 的 512 个值与 `round(32767*sin(2*pi*i/512))` 逐点比较，最大误差 0，波形上下半周期严格反对称。波表本身是干净的，问题不在数据。

### 定位到相位截断

原实现只用 `phase[31:23]` 查表，下面 23 位相位全部丢弃。阶梯误差是一个以基频为周期的函数，它的谐波一直延伸到几百个谐波次数。采样率只有 46.875 kHz，Nyquist 是 23.4 kHz，凡是超过这个频率的谐波都会折回可听频段，例如 100 次谐波 44 kHz 折到 2.875 kHz，54 次谐波 23.76 kHz 折到 23.1 kHz。听感就是叠在纯音上的一层细密闪烁噪声。

用 65536 点频谱模型量化，结果如下。

| 版本 | 误差均方根 | 带内误差功率 |
| --- | --- | --- |
| 原来（512 点直接查表） | 164 个码值，-46.0 dBFS | -42.99 dBc，最强杂散 9.5 kHz 处 -57 dBc |
| 现在（线性插值 + (1,2,1)/4 平滑） | 0.6 个码值，-94.8 dBFS | -91.90 dBc，最强杂散 16.5 kHz 处 -111 dBc |

改善 48.8 dB。16 位系统的底噪是 -96 dBFS，改进后的误差已经落在这个量级，属于听不出来的水平。

### 三处改动

`dds_osc.v` 加入线性插值：`phase[31:23]` 选表项，`phase[22:14]` 作为 9 位小数，在 `wave_rom[idx]` 与 `wave_rom[idx+1]` 之间插值。插值把一阶阶梯误差变成二阶误差，这是 -49 dB 的主要来源。插值结果先打一拍再输出，`voice.v` 里的包络乘法因此没有被串进同一条 37 ns 组合路径；实测 Fmax 115.474 MHz，与改动前的 113.169 MHz 基本持平。

`top.v` 在音量控制之前加了两级两抽头平均，等价于 (1,2,1)/4 低通。频响是 cos²(πf/fs)：440 Hz 处 -0.008 dB，8.5 kHz 处 -3 dB，15 kHz 处 -11 dB，Nyquist 处为零点。只用加法和移位，不占额外 DSP。这一级负责把插值之后残留的高频成分再压下去。

`top.v` 的音量控制改成先加 `1<<(SHIFT-1)` 再右移，去掉截断引入的信号相关直流台阶。

### 本轮资源

968 个 LUT/ALU、237 个寄存器、1 块 BSRAM（两次查表被映射成同一块 ROM 的双端口）、2 个 18×18 乘法器和 1 个 PADD18。0 个建立违规、0 个保持违规。

## 二、S4 按键与程序失效

### 现象

按下底板上的 S4 后整板复位，刚才烧进去的程序失效。

### 按键真实连接

从 Dock 3714 原理图 `P007_Things` 页出发追踪五个 Silicone Key 的走线，再到核心板 SOM-3961 原理图确认这些网络在 FPGA 侧的用途，并用 Sipeed 开箱指南和底板照片交叉验证。

| 丝印 | 原理图网络 | FPGA 引脚 | 作用 |
| --- | --- | --- | --- |
| S0 | `T10_IOR35B_FPGA_~RST` | T10 | 普通 IO，官方固件拿它当复位输入 |
| S1 | `T3_IOB52B_1V5` | T3 | 普通 IO，本工程用作 C4 |
| S2 | `T2_IOB48B_1V5` | T2 | 普通 IO，本工程用作 C5 |
| S3 | `D7_IOL53B_1V5` | D7 | 普通 IO，空闲 |
| S4 | `B10_IOR31B_~{RECFG}` | B10 | RECONFIG_N，按下触发 FPGA 重新配置 |

SOM 原理图里的引脚名写得很清楚：`B10 = IOR31B/RECONIG_N`（原图把 RECONFIG 拼成了 RECONIG），而 `T10 = IOR35B/D2` 是普通数据脚，只是网络名叫 `FPGA_~RST`。

### 为什么程序会失效

GW2A 上电或 RECONFIG_N 被拉低时会重新载入配置，配置源由 MODE0/1/2 三个引脚决定，通常是板载外部 SPI Flash（核心板上 M9/L10/R10/P10 四根线就是 FLASH_SPI 的 CS、CLK、SI、SO）。通过 JTAG 烧录默认写的是 FPGA 内部的 SRAM，掉电即失；按 S4 触发重配置，等于让 FPGA 放弃 SRAM 里的内容，改从 Flash 加载，而 Flash 里要么是出厂固件、要么是空的，所以刚才的程序就没了。这是 SRAM 易失配置的固有行为，不是板子坏了。

### 正确做法

想要一个"复位"按键，应该用 S0/T10 或 S3/D7 这类普通 IO，在 RTL 里做一个同步复位，而不是依赖 S4。想让程序在重配置和断电后依然存在，需要把码流写进板载外部 SPI Flash：高云编程器的操作 9 是 `exFlash Erase,Program,Verify`，图形界面里对应 Access Mode 选 External Flash Mode、Operation 选 Erase, Program, Verify。

写入 Flash 后可以这样验收：按一下 S4 触发重配置，设计应该自动从 Flash 恢复并且 LED 继续闪烁、耳机继续出声。如果按 S4 后板子彻底没反应，说明 MODE 引脚没有选到主 SPI 配置模式，或者 Flash 写入没有成功。

## 三、图形界面烧录

本轮不再用命令行，改为打开图形界面：

- Gowin IDE：`E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_ide.exe`
- 独立编程器：`E:\Gowin\Gowin_V1.9.11.03_Education_x64\Programmer\bin\programmer.exe`

工程文件是 `.../source/build/gowin_single_voice/instrument/instrument/instrument.gprj`。IDE 本次启动停在 Start Page，命令行传工程路径没有生效，需要手动 File → Open Project。编程器界面里的设置顺序是：Cable 选 `Gowin USB Cable(FT2CH)`，Device 选 `GW2A-18C`，Access Mode 选 External Flash Mode，Operation 选 Erase, Program, Verify，Bitstream 选 `artifacts/instrument.fs`，然后点 Program/Configure。

## 四、当前码流

修订三码流 `artifacts/instrument.fs`，SHA256 `4095ed01d1b8c2d89aec808e06ebe846047089063cf7a67ff24a518d60aabed6`，User Code `0x000071A6`，已用 SRAM Program 写入，退出码 0。

## 五、待确认

- 戴上耳机确认闪烁噪声是否已经听不出来。
- 确认按 S4 不再用于复位，改用 RTL 内部复位。
- 如果打算让程序常驻，用图形界面做一次 exFlash Erase, Program, Verify，然后用 S4 触发重配置验证能否自动恢复。
