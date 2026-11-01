// [S3-AI | deepseek | 2026-10-14] 统一时钟与采样率参数的唯一来源。
//
// 目的：把「时钟频率 / 采样率 / I2S 帧格式」集中到一处，新发送器、测试和指标
// 使用同一档案，避免分频常数散落到各模块。i2s_tx 用 module parameter 接收这两个值，
// 模块内部只出现由参数推导出的 localparam；档案由实例参数或构建时选择，不做运行时切钟。
//
// 两个档案（依据 TI SLAS859C 表 2/表 11 与 docs/minimum_design/01_时钟配置.md）：
//   标准档案：外部 12.288 MHz 有源晶振直接作系统时钟，Fs = 48 kHz，
//             每帧 64 个 BCK，BCK = 3.072 MHz，配 PCM5102A 标准 I2S。
//             对应 top 的 AUDIO_IF=1 / 构建档 standard；需要 T7 外接晶振。
//   27 MHz 档案：板载 27 MHz（H11），Fs = 46.875 kHz，每帧 64 个 BCK，
//             BCK = 3.000 MHz，BCK 周期 9 拍（高 4 低 5）。
//             对应 top 的 AUDIO_IF=2 / 构建档 standard27；不需要外部晶振。
//             它与 48 kHz 档共用这里的 DBG 常数（CLK=27 MHz、FS=46.875 kHz），
//             不是“近似 48 kHz”：27e6/9/64 = 46875 是精确整数分频。
//   调试档案（AUDIO_IF=0）：同一组 27 MHz 常数，但走板载 PT8211 的 18 拍 BCK 帧。
//
// 采样率只有 48 kHz 与 46.875 kHz 两档；两者都按 FS_HZ 生成相位增量与时间常数，
// 音高不因档位变化。46.875 kHz 档不能冒充 48 kHz 指标，报告里必须写实际值。
//
// 本头文件只接入 S3 新增模块与测试；既有顶层的默认 27 MHz / 46 875 Hz 不变。
// 既有合成链的迁移清单（后续集成时逐项复核，不能只改这里）：
//   顶层/POR/同步去抖  唯一 sample_tick 来源；去抖计数按实际时钟推导；GPIO 响应拍数重测
//   uart_ctrl.v        CLK_HZ 常数与波特率分频
//   note_phase_inc.v   十二个半音相位增量按 46875 Hz 生成，改 48000 Hz 需重生成
//   song_player.v      每拍样本数与节拍换算
//   adsr.v / mixer.v   包络时间、控制平滑与 FIR 频响/延迟
//   pt8211_tx.v        旧 18 拍 BCK 分频在 12.288 MHz 下不成立
//   tb_tick_rate.v     期望节拍 576 clk
//   analyze_audio_capture.py   FS = 46875
//   run_audio_verification.ps1 reproduction.json 的 clock_hz / sample_rate_hz

`ifndef FPGA_AUDIO_CLK_PARAMS_VH
`define FPGA_AUDIO_CLK_PARAMS_VH

`define FPGA_AUDIO_STD_CLK_HZ   12288000
`define FPGA_AUDIO_STD_FS_HZ    48000

`define FPGA_AUDIO_DBG_CLK_HZ   27000000
`define FPGA_AUDIO_DBG_FS_HZ    46875

// 标准 I2S 每帧固定 64 个 BCK 周期，即每声道 32 个槽。
// 每声道位置 0 是零延迟位，位置 1..DATA_BITS 是数据（MSB 在前），其余发 0。
// DATA_BITS 取 16 或 24：16 位布局为「0 + 16 位 + 15 位零」，24 位为「0 + 24 位 + 7 位零」。
`define FPGA_AUDIO_SLOTS_PER_FRAME 64

`endif
