# Flash 烧录与演奏快捷方式（2026-10-19）

## 烧录

- 构建档：`standard27`（27 MHz / 46.875 kHz / 8 声部 / 柔化波表）
- 构建 run：`build/gowin_top_i2s_std27/runs/20261019T123230967-8506dfc8`
- 位流 SHA256：`000C9A86D9C1B454B849CECA36E2D1D6C7B515947F990B85460C229ED58EABB4`
- 编程器：`E:\Gowin\Gowin_V1.9.11.03_Education_x64\Programmer\bin\programmer_cli.exe`
- 电缆：`Gowin USB Cable(FT2CH)/0`，2.5 MHz
- 器件：`GW2A-18C`，ID `0x0000081B`
- 操作：**37 `exFlash Erase,Program,Verify thru GAO-Bridge`**
- 结果：`Program and Verify flash successfully.`，退出码 0，耗时 26.7 s
- 烧录后读码：User Code `0x00000DAD`，Status `0x00006020`

普通操作 9 在这块板子上曾出现 `SPI Verify failed`（退出码仍为 0），本次沿用 2026-10-14 验证过的操作 37。

## 仿真门禁

按用户此前“依旧跳过长耗时门禁”的明确要求，本次烧录使用 `-SkipSimulation`。烧录前已通过的定向测试：

- `tb_piano_bank`：72 张重生成表 × 512 地址一致
- `tb_piano_stage`：新阶段映射
- `tb_engine8_pitch`：8 声部 A4 正弦 106.50
- `tb_top_pitch8`：8 声部顶层 A4 正弦 106.43

完整 `run_simulation.ps1` 未跑。这不符合项目“烧录前必须过完整门禁”的默认规则；风险是旧测试台可能因波表重生成而持有过期黄金向量，不代表新位流功能失败，但本次没有用完整门禁证明这一点。

## 演奏窗口

- 桌面快捷方式：`C:\Users\ROG\Desktop\PolyTouch 电脑演奏.lnk`
- 开始菜单：`%APPDATA%\Microsoft\Windows\Start Menu\Programs\PolyTouch 电脑演奏.lnk`
- 目标：`powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "E:\Working Space\FPGA\tools\serial_keyboard\keyboard.ps1"`
- 启动验证：窗口 PID 10520，标题 `PolyTouch 电脑演奏`
- 串口日志 `output/serial_keyboard/keyboard-20261019-145132.log`：`D0 -> OK`、`M1 -> OK`

## 待确认

Flash 校验通过，但**冷启动持久性**还没有做断电验证。请彻底断电再上电（或按 S4 触发重配置），然后从桌面快捷方式打开窗口；若仍能 `D0/M1 -> OK` 并出声，才可把“Flash 持久化”标记为通过。User Code 已从烧录桥的 `0xB8DF` 变为 `0x0DAD`，说明器件已重新配置，但这不是冷启动证据。

## 工具修复

`program_sram.ps1` 的 UTF-8 BOM 在之前编辑中丢失，PowerShell 5.1 按 GBK 解析中文会报语法错误；已补回 BOM。`run_simulation.ps1` 之前也做过同样修复。

## 追加：无外设，改烧板载 PT8211 档（14:55）

用户确认当前没有任何外设，全部用板载资源；`standard27` 只驱动外置 PCM5102A（B12/C12/B13/P6），板载 PT8211 耳机口（N15/P16/P15/R16）在这档静音，所以“按键 OK 但没声”是档位与接线不匹配，不是按键链路故障。

已新增并烧录 `debug8` 档：

- 顶层 `top_dbg8_build`：`AUDIO_IF=0`、`VOICES=8`、`MASTER_VOLUME_SHIFT=3`，板载 PT8211 / 27 MHz / 46.875 kHz。
- 位流：`build/gowin_top_dbg8/runs/20261019T145432461-1ade3655/instrument/impl/pnr/instrument.fs`
- 指标：Logic 9383（46%）、Register 3113（20%）、BSRAM 40/46、MULT 1、Fmax 34.121 MHz、Setup/Hold 违规 0。
- Flash 操作 37：`Program and Verify flash successfully.`，26.9 s。
- 重新打开演奏窗口：PID 16968，`D0 -> OK`、`M1 -> OK`。

当前生效的是板载耳机口 8 声部档。若仍无声，下一步用已知能出声的 `debug`（4 声部 PT8211）做对照，区分硬件/耳机口与 8 声部路径。
## 追加：统一钢琴+吉他档与 UI 切换（15:36）

- 档位：`debug8`，同时包含钢琴 72 表、通用 6 表、吉他 6 表；新增 `I0/I1` 运行时切换，切换拍清声部/事件。
- 位流 SHA256：`27969F20D05412BE0D461888F33BBEF6E80EC4314629FA2C36A918169C2DD46E`
- 指标：Logic 10533（51%）、Register 3296（21%）、BSRAM **43/46（94%）**、MULT 1、Fmax **33.334 MHz**、Setup/Hold 违规 0。
- Flash 操作 37：`Program and Verify flash successfully.`，26.96 s。
- UI：新增“音色：钢琴/吉他”按钮与 **F6**；实测键盘 `F6` 两次，日志 `I1 -> OK`、`I0 -> OK`、`T254 -> OK`。
- 定向测试：`tb_top_switch` PASS（I0→I1→I0、清声部、表重选）、`tb_guitar_bank` PASS、`tb_host_kbd` PASS、`tb_top_pitch8` PASS。
- 门禁：按用户“可以跳过时间过长的验证”与“统一烧录”要求使用 `-SkipSimulation`；完整 `run_simulation.ps1` 未跑。
## 追加：AKWF 电钢琴 + Karoryfer 吉他 18:18（15:54）

- 钢琴：`AKWF_epiano_0001`（CC0）→ 36 表（6 音区 × 6 阶段），18 BSRAM。
- 吉他：Karoryfer Black And Green（CC0）`green/black × p/mf/f` → 36 表（6 频段 × 6 变体），18 BSRAM。
- 合计 BSRAM **40/46**（钢琴 18 + 吉他 18 + 通用 3 + 正弦 1），表数 36:36。
- 位流 SHA256：`CE9C5D3204E52BFDFF9CCA356AD760CE24B1D224DCE73ED824001A41BFA05ABF`
- 指标：Logic 10544（51%）、Register 3293、MULT 1、Fmax **36.081 MHz**、Setup/Hold 违规 0。
- Flash 操作 37：`Program and Verify flash successfully.`，27.04 s。
- UI 实测：`T252/N48/O48` → `I1/N48/O48` → `I0/T252/N48/O48`，全部 OK。
- 定向测试：`tb_piano_bank`、`tb_guitar_bank`、`tb_piano_stage`、`tb_top_switch` PASS。
- 门禁：按用户要求使用 `-SkipSimulation`；完整 `run_simulation.ps1` 未跑。
## 追加：吉他低音毛刺修复（16:01）

- 根因：时域取一个周期的首尾不闭合（最低表 wrap/median=20.5），且 0.30 s 取样已衰减到噪声、默认力度映射到 black/p。
- 修复：精确 f0 谐波分解 + Goertzel + −62 dB 噪声门 + 6.5 kHz 低通，合成严格周期表；取样提前到 0.08 s；低音区默认 green/f。
- 位流 SHA256：`27A0816E94BEA7A68B22254D70FCF2E95B35135575D6D851E7F0A9DF795C4070`
- 指标：Logic 10612（52%）、Register 3293、BSRAM 40/46、MULT 1、Fmax 34.800 MHz、违规 0。
- Flash 操作 37：`Program and Verify flash successfully.`，32.76 s。
- 验证：`tb_guitar_bank` PASS；低音表 5 kHz 以上能量 6.2% → 0%，最大步进 3979 → 671。
- 门禁：按用户要求 `-SkipSimulation`；完整 `run_simulation.ps1` 未跑。
## 追加：高音区尖锐优化（16:09）

- 主混合后加一阶低通：`mix_lp_y += (mixed_shared - mix_lp_y) >>> 1`，a=0.5，fc≈5.2 kHz；只用移位。
- 位流 SHA256：`A1B2A2AC28CD9A81EAD7D28496382605826D9192D5673FBBC6FC0D9B1B6A685C`
- 指标：Logic 10647（52%）、Register 3309、BSRAM 40/46、MULT 1、Fmax 33.703 MHz、违规 0。
- Flash 操作 37：`Program and Verify flash successfully.`，27.43 s。
- UI 重开：`D0 -> OK`、`M1 -> OK`。
- 门禁：按用户要求 `-SkipSimulation`；完整 `run_simulation.ps1` 未跑。