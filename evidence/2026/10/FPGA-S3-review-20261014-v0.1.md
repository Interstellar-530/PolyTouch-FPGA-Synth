# S3 复核与修正记录（2026-10-14 v0.1）

原实现：DeepSeek，提交 `37bdb62`，分支 `codex/s3-i2s-tx`；本轮复核与修正：Codex。用户授权核查、优化、在全部检查通过后推送 Git 并更新 S3 清单。原九个 S3 源码/构建文件保留 `[S3-AI | deepseek | 2026-10-14]`，修正处加 `[S3-REVIEW | Codex | 2026-10-14]`，不将复核代码归为原作者。

本轮结果：S3 数字模块复核通过；十三台正向门禁、六个参数负例、三种检查器故障注入、原 PT8211 音频回归，以及真实 16/24 位配置的隔离综合/PnR 全部通过。未修改生产顶层、生产 CST/SDC、全局配置或板内程序，PCM5102A 实机仍待验收。本地归档为 `archive/FPGA-20261014-v0.7`。

## 发现与修正

| 问题 | 修正与验证 |
| --- | --- |
| 隔离综合的 `data_bits` 参数未使用，两份报告实际都是默认16位 | 为每个变体生成明确位宽的包装源，保留源码、网表和报告；24位资源已与16位不同 |
| 接收模型只在 BCK 上升沿观察复位，发送端停 BCK 时会保留旧配对 | 行为模型异步清除未完成状态；人工位串测试专门覆盖 BCK 停止时复位，删除该复位处理的变异代码被拒绝 |
| 复位非零探针被后续普通激励覆盖，右探针本身还是零；第一轮注入位置也非原文描述 | 复位阶段保持双路非零探针，按左数据、右数据、填充槽安排三次注入，每次实际恢复字逐项检查 |
| 填充位只被忽略，缺少全零断言；tick只检查出现时的宽度，缺少边界必有tick的检查 | 新增原始32槽填充位与tick/帧边界双向断言；填充损坏及缺失tick的变异代码均按指定原因失败 |
| `BCK_CYC=4` 被保存到2位常数后截断成零，靠减一绕回工作，产生 EX3791 警告 | 保存可表示的末值 `BCK_CYC-1`，去掉未使用的左保持寄存器和上升沿信号；两档仿真及零警告综合通过 |
| 模块默认时钟未读取统一头；调试档模拟时钟误差被写为0.03ppm | 模块、包装默认值使用参数头，测试时钟由档案生成；37.038ns 的周期误差为+26ppm、频率约-26ppm，数字验收按系统拍计数 |
| S3指标写入共享tmp目录，可能与验收运行混淆 | 完整回归为本次运行单独保存metrics；保存参数原始FATAL日志，必须退出1且原因匹配；补零时钟负例 |
| 非ASCII plusargs会破坏路径；默认门禁在源码目录留下.vvp | 对运行目录提前检查ASCII，默认构建移到tmp；保留原失败日志，不绕过编译退出码 |
| Gowin创建工程改变当前目录；仅回源码根会把报告落进生产源码impl目录 | 隔离工程临时复制同一参数头，产物全部落在明确tmp工程；批处理显式成功/失败退出，最终构建退出0 |

以上为常规可逆修正，未改变发送器公共端口或项目时钟架构。回退可撤销本轮提交或从归档 `source_before/before/` 恢复相应文件；不要对用户其他改动执行全局 reset/clean。DeepSeek 原先移动到 `legacy/pending_removal` 的四项内容经 Git 检查为100%重命名，本轮不删除或再次搬动；采购相关三个未提交文件保持原样。

## 验证证据

完整运行退出0，`verification_result.json` 中 `rtl_gate_exit=0`、`analysis_exit=0`。门禁日志末行确认十三台正向与六个参数负例通过；原始逐台诊断包含在 `simulation_gate.log`，六个参数原始日志在 `metrics/param_*.log`。固定随机种子仍为 `32'h53A32026`。

| I2S组合 | 检查完整帧 | 每帧系统拍 | BCK高/低拍 | 定向/随机/撕裂/静音帧 | 非零复位恢复 |
| --- | ---: | ---: | --- | --- | ---: |
| 标准16位 | 285 | 256 | 2/2 | 16/208/24/16 | 3 |
| 标准24位 | 285 | 256 | 2/2 | 16/208/24/16 | 3 |
| 调试16位 | 279 | 576 | 4/5 | 16/208/24/16 | 3 |
| 调试24位 | 279 | 576 | 4/5 | 16/208/24/16 | 3 |

引脚解码、帧锁存与静音恢复均通过，模型残段丢弃计数为0。三个故障注入分别以 `S3_PADDING_NONZERO`、`S3_TICK_BOUNDARY`、`S3_RX_RESET_STALE` 拒绝，退出码1；复现脚本为 `tools/verify_s3_review.ps1`，临时变异源码不进入生产工程。

音频回归捕获58,880帧，A4估计439.9999746619Hz；四频、逐个松键、释放归零与数字静音通过，分析器八个负面用例通过。JSON、图表和WAV在本记录同名证据目录，原始CSV与清单在本地归档。音频数据仍是27MHz/46,875Hz的PT8211原路径，不能当作48kHz实机I2S证据。

| 隔离配置（含包装） | 逻辑单元 | 寄存器 | Fmax MHz | setup/hold违例 |
| --- | ---: | ---: | ---: | --- |
| 标准16位 | 93 | 68 | 224.930 | 0/0 |
| 标准24位 | 125 | 92 | 217.408 | 0/0 |

Gowin V1.9.11.03 Education，GW2A-LV18PG256C8/I7版本C，81.38ns约束；最终日志无WARN/ERROR，结构不占BSRAM/DSP。时序通过仅针对隔离工程内部约束，不证明DAC引脚建立/保持或板级信号完整性。完整链接的时序HTML、包装源和综合网表均保留，避免只保留空的HTML frameset。

## 日志风险的处理结论

Icarus编译沙箱兼容问题沿用已记录的外部执行方式，本轮没有修改全局设置、忽略非零退出或使用旧.vvp。音频捕获期间目录显示大小未更新，曾被误判为停滞；临时跟踪确认时间和帧数持续推进，直接读取捕获末行也确认有效数据，正式回归最终通过。两次额外诊断进程已按命令行确认后停止，不把诊断副本当验收证据。

前两次Gowin尝试分别暴露参数头包含路径和产物目录问题，日志保留为 `gowin_attempt1.log`、`gowin_attempt2.log`；最终证据采用 `gowin_release.log`。旧辅助构建未可靠收尾的问题通过最终脚本显式exit解决，最终运行退出0，不沿用前次进程的状态。

仍待T04：12.288MHz晶振额定电压和实际频率、GCLK/Bank与候选引脚落地、DAC丝印/FMT/SCK/XSMT、唯一采样tick和DDS/UART/去抖/ADSR/曲目参数迁移、I2S引脚与实际发声及整机≤10ms测量。27MHz调试档4:5占空比的实物兼容性也未测。SCK三线模式与FMT依据[TI官方资料](https://www.ti.com/product/PCM5102A)及既有手册复核页。本轮只划去S3数字交付，不提前划去这些实机项。

## 复现

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_audio_verification.ps1 -OutputDir tmp\s3_new_run
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\verify_s3_review.ps1 -OutputDir tmp\s3_new_mutations
$env:FPGA_I2S_SYNTH_OUT_DIR = 'E:\Working Space\FPGA\tmp\s3_new_gowin'
powershell -NoProfile -ExecutionPolicy Bypass -File .\output\handoff_milestone2_20261008\source\build\build_i2s_tx.ps1 -GwSh 'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe'
```

使用未占用的ASCII运行目录。证据输入绑定和标签检查见 `binding_check.json`，归档有MANIFEST、CHANGES、REPRODUCE和SHA256。清理仅限本轮列出且解析后的路径，保留源文件、脚本、关键证据与原始数据，不处理既有工具环境或用户其他临时内容。
