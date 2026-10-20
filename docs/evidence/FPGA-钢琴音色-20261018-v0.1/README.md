# 钢琴风格波表与击弦包络

日期：2026-10-18。代码基线为 `ff2c7d6` 加本轮未提交改动。该实现仍是单周期钢琴风格合成，不是采样回放：72 张 512 点表按 6 个音区、2 个力度层、6 个包络阶段排列；音符起音时锁存钢琴模式并切换到独立击弦包络，包络衰减时在相邻阶段间插值。

## 实现

`gowin_prom_piano_bank.v` 使用 36 块 pROM 存储 72 张钢琴频谱表，bank 地址为 `zone*12 + velocity_layer*6 + stage`。`shared_wavetable_engine` 根据音高、力度和每声部包络选择相邻表并插值，T250–T254 选择五档基础硬度。`voice_transition` 增加钢琴模式锁存与第二组 ADSR，默认起音约 0.68 ms、按住时约 0.70 s 线性衰减到低尾音、释音约 87 ms（满幅计）。电脑窗口 F1–F5 对应 T250–T254。

72 张表的频谱来自 Salamander Grand Piano v3 的 C1–C6 弱/强力度样本（Alexander Holm，CC BY 3.0）。每个音区取六个时间窗的前 10 次谐波相对幅度和共同相位，不把原始 OGG/PCM 拷入 RTL。六个包络阶段从强击弦逐步过渡到柔和琴体，表内最高谐波在默认键盘上限 B6 下仍低于 Nyquist。

## 验证

`tb_piano_bank` 逐点比较 72 张表各 512 个地址并通过；`tb_piano_engine` 验证 C4 强力度击弦 bank，`tb_piano_morph` 验证包络在 body/hammer 间选表；`tb_piano_envelope` 验证模式在起音时锁存、按住会衰减到静音、松开后回到 idle。`tb_timbre_top` 通过真实 UART T250–T254、真实 I2S、四声部相位连续和 114 拍/42 次乘积检查。键盘自检通过 F1–F5 对应 T250–T254。

额外定向回归：架构等价、共享弯音、帧力度、音色控制、音色音频、T254 顶层、声部过渡音频、宽精度音频均通过。`tb_voice_transition_audio` 的高频残余合计降低 32.02 dB，`tb_precision_audio` 满包络宽精度 SNR 为 92.39 dB。

真实 Gowin 布局布线资源为 5347 Logic、1866 Register、37/46 BSRAM、1 个 MULT18X18；逻辑占用 26%，剩余 9 块 BSRAM。该报告是板载专用 `board_only_top`，不是完整生产封装的最终时序签核。

最终板载位流 `board-72zones/board_only.fs` 的 SHA256 为 `053A2E23EA10C5AE70381F190AC4F28A9AB15713ED3CFC4B5C5AA4DC3C19167A`。JTAG SRAM 烧录成功，读回 User Code `0x000042F6`；COM13 实测 `D0/M1/T250/T251/T252/T253/T254/N60/O60/X` 全部 OK。Flash 未改写，断电恢复旧程序。

## 边界

按用户要求跳过了全量门禁，因此没有完整门禁通过记录。钢琴仍是单周期波表加线性包络，缺少真实钢琴的非周期敲击瞬态、弦耦合和非整数谐波；72 张多音区/力度/阶段表只改善频谱结构，不能替代采样钢琴。M0 静音下板载模拟链路仍有底噪，需通过外置 DAC/独立耳放或低噪声供电解决。当前生产仍是四声部。
