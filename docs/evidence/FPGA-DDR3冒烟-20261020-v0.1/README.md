# PolyTouch DDR3 冒烟验证（2026-10-20 v0.1）

## 目的

完整采样吉他方案需要把多秒 16 位采样放进 DDR3，再由 8 个声部通过预取 FIFO 流式读取。这个目录先验证最底层、风险最高的部分：Tang Primer 20K Dock 的 128M DDR3 能否在当前 Gowin 工具链下完成校准、写入和回读。

这不是吉他采样播放器，也没有改动主项目的 `top.v` 或现有位流。

## 来源与许可

- 基线：Sipeed `TangPrimer-20K-example` 的 `DDR-test/LicheeTang20K_DDR_Test`
- 仓库：`https://github.com/sipeed/TangPrimer-20K-example`
- 提交：`e469df4c0c9c41824f405a8515decf24ef1e8e6f`
- 许可证：BSD-3-Clause，见 `LICENSE`
- DDR3 控制器：Gowin `DDR3_Memory_Interface_Top` 生成 IP，随工程保存在 `src/ddr3_memory_interface/`
- 板卡：Sipeed Tang Primer 20K Dock 3714，GW2A-LV18PG256C8/I7，版本 C
- 工具：Gowin V1.9.11.03 Education x64

## 相对原例程的修改

1. 新增 `src/ddr3_smoke_top.v`，把测试器、PLL 和 DDR3 控制器组织成独立冒烟顶层。
2. 修正原 `ddr3_syn_top.v` 中 `O_ddr_cs_n` 接到未使用 `ddr_cs1`、同时把 `ddr_cs` 固定拉低的问题；现在片选由控制器驱动。
3. 新增 `led` 输出，接板载 N16（Orange_LED2），点亮表示 `init_calib_complete=1`。
4. 新建 `build.tcl`，固定使用本机 Gowin 工具和 3714 DDR3 引脚约束。

## 构建结果

构建命令：

```powershell
& 'D:\Gowin_V1.9.11.03_Education_x64_win\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe' '.\build.tcl'
```

已通过综合、布局布线、时序分析和位流生成：

| 项目 | 结果 |
|---|---|
| Logic | 3320 / 20736（17%） |
| Register | 1926 / 16173（12%） |
| BSRAM | 13 / 46（29%） |
| IOLOGIC | 120 / 207（58%） |
| Setup 最差裕量 | +0.001 ns，0 条负裕量 |
| Hold 最差裕量 | +0.234 ns，0 条负裕量 |
| 位流 | `src/impl/pnr/ddr3_smoke.fs`，7,264,154 字节 |
| SHA256 | `0AE0BC3CDD5DE6971EF2F5BB0F7B3DE72074F4FDB9C54CC7E40E7D7946EAD97A` |

Setup 裕量只有 0.001 ns，属于非常紧的通过。必须上板验证，不能只凭综合结果宣称 DDR3 已经可靠。

## 上板验证步骤

1. 用 USB-JTAG 连接板卡，确认 `programmer_cli --scan-cables F` 能识别 Gowin USB Cable(FT2CH)。
2. 用 SRAM 编程操作 2 烧录 `src/impl/pnr/ddr3_smoke.fs`；不要用操作 4。
3. 观察 N16 LED：点亮表示 DDR3 校准完成。若一直不亮，先检查 DDR3 供电、核心板是否插好、器件版本和引脚约束。
4. 用串口工具连接 USB-JTAG 串口，115200 8N1。原测试器会在 `init_calib_complete` 后打印初始化信息，随后执行全片写入/回读并报告 `Check Finished without Mismatch` 或 `Check Failed`。
5. 记录实际输出、LED 状态和耗时到 `evidence/`，再决定是否进入采样播放器阶段。

当前这台电脑没有识别到板卡串口（只有 Bluetooth COM3/COM4），所以上板验证尚未执行。

## 边界

这个工程只验证 DDR3 控制器和读写链路，不包含吉他采样、8 声部预取 FIFO、Flash 加载或音频输出。完整采样方案仍需：

- 将 12 个原始采样裁剪、重采样并打包成 DDR3 可读的 128 位字流；
- 设计每声部预取 FIFO 和 DDR3 突发仲裁，避免逐样本随机访问 DDR3；
- 设计音频时钟 46.875 kHz 与 DDR3 用户时钟 100 MHz 之间的 CDC；
- 解决上电后 DDR3 内容丢失，确定从 32 Mbit NOR Flash 还是 PC/UART 加载采样；
- 接入现有 8 声部包络、混音、I2S/PT8211 和 UART 控制；
- 重新跑完整 RTL 门禁并做上板音频验收。

## 复现

```powershell
.\commands\build.ps1
```

或直接执行 `build.tcl`。程序文件、报告和校验记录见 `MANIFEST.md` 与 `checksums.sha256`。