# 测试曲换曲证据（2026-10-24，v0.1）

把内置测试曲从《兰花草》换成《晚夜微雨问海棠》副歌，生成约 59.26 秒、原速 81 BPM 的测试音频，并更新板内曲目表。

## 改动范围

| 文件 | 改动 |
| --- | --- |
| `source/tools/song_data.py` | 新旋律、节奏槽与两套和弦；速度 81 BPM |
| `source/tools/gen_song_rom.py` | 旋律表 256 项、和弦表 64 项，新增 `song_expect.vh` 常量 |
| `source/rtl/audio/song_player.v` | 索引位宽 8/6；每项由“发声时长”改为“槽长”，气口由槽长推导 |
| `source/rtl/audio/song_roms.vh`、`song_expect.vh` | 由脚本重新生成 |
| `source/rtl/top.v` | 单位采样 8681（46.875 kHz）/ 8889（48 kHz）；上电档改为 1x；旋律索引 8 位 |
| `source/sim/tb_song_timing.v` | 适配 8 位索引；长跑改为短单位 + 参数参照实例 |
| `source/tools/render_preview.py`、`verify_preview.py` | 适配槽长语义和默认文件名 |
| `source/sim/reference/baseline_top.v` | 索引位宽同步 |
| `output/handoff_milestone2_20261008/SONG_WANYE_WEIYU.md` | 新测试曲说明 |

## 试听文件

| 文件 | 长度 | 峰值 | SHA256 |
| --- | --- | --- | --- |
| `artifacts/wanye_chordA.wav` | 59.262 s，2,777,920 采样，46875 Hz 单声道 16 位 | −2.9 dBFS | `7B823AC0240D421E5A85F16B993543F9D1F7BF9E9A586D9F683BFE22325AA317` |
| `artifacts/wanye_chordB.wav` | 同上 | −1.6 dBFS | `948915A06B8AF1967A93992BD0F55BD179C6207D64F35CEA7C0F36014C8EDF46` |

A 套是琴谱123 副歌和声（F G / Am / C / Dm Em），B 套是弹琴吧钢琴改编谱的左手循环（F G / Em Am）。两套都通过逐音校验。

## 验证结果

| 项目 | 命令 | 结果 |
| --- | --- | --- |
| 曲目表自检 | `python tools/song_data.py` | 通过：20 小节、320 槽、旋律 146 项、和弦 A/B 各 40 项 |
| 逐音试听校验 A | `python tools/verify_preview.py ..\artifacts\wanye_chordA.wav 1` | 146 个旋律事件，0 失败 |
| 逐音试听校验 B | `python tools/verify_preview.py ..\artifacts\wanye_chordB.wav 1` | 146 个旋律事件，0 失败 |
| 曲目时长专项 | `run_simulation.ps1 -Tests tb_song_timing,tb_song_backpressure` | 2/2 通过；一遍 320×97 采样、256 个 note-on |
| Quick 门禁 | `run_simulation.ps1` | 18 项检查通过（12 正例 + 6 参数负例），79.1 s |

`gate-song-result.json` 是定向门禁的原始结果，`gate-quick-result.json` 是 Quick 的原始结果。

## 关于 Quick 门禁的快照

共享源码树在 2026-10-24 10:38–10:42 有另一项并行任务写入 `sim/opt_a/*`，两次在真实源码树里跑的 Quick 都在结束时报 `Source changed during simulation`（所有测试本身通过，但结果被门禁判为无效）。最终结果是在只含 `rtl/` 与 `sim/` 的冻结副本上重跑的：

```
E:\Working Space\FPGA\tmp\gate-snapshot-wanye\source
```

该副本的 `song_player.v` SHA256 与生产源码一致（`A33F1B543556F5A150F928C20A1CCC24704D7460CB924C98CAADB70855F780D4`），Quick 才得到干净的 18/18。并行任务停止后，仍建议在真实源码树里再跑一次 `run_simulation.ps1`，再把 `gate-result.json` 作为烧录收据。

## 未完成

- 没有重新综合/布局布线，也没有生成新位流。首次烧录前应由 `program_sram.ps1` 重新跑门禁并构建对应档位。
- 没有做板级试听；WAV 是 RTL 等价金模型的输出，不是板上录音。
- 原曲是降 E 调，本测试曲用公开 C 调谱的读法（低小三度），速度不变。

## 2026-10-26 修版 v8（已更新到演示曲目）

按钢琴谱上每个音符的横向位置逐小节重算格位，修正第 4、6、8、9、10 小节；“为你闯一趟”现在是 D5×3 E5×3 G5×1 E5×1 E5×4 D5×2 E5×2。

- 正式 `artifacts/wanye_chordA.wav`、`wanye_chordB.wav` 已用 v8 覆盖；两套逐音校验各 138 事件、0 失败。
- 真实源码树 Quick 门禁 **20/20 通过**（112.67 s，含并行任务新增的 tb_fsr_mute、tb_top_host_pause）；曲目专项 2/2 通过。
- 原始结果：`gate-quick-v8-result.json`、`gate-song-v8-result.json`。
- ROM：138 项、136 个发声、`MELODY_LAST=137`；320 个十六分槽、256 个 note-on。
- 仍未重新综合/生成位流；烧录前按门禁规则重新构建。

## 第二首候选：《旷古回响》bridge

- 音频来源：YouTube `lB0_ACs8aJ8`（全曲 5:41）。
- LRC 时间轴：4:20“巍峨西山古 浩瀚大河雄”、4:29“兴亡陈迹今只余”、4:39“摄衣瞻拜太史公”、4:43“千载斯文在此种”。
- 摘录 4:15–4:52（37 s，48 kHz 单声道，1.2 s 淡入淡出）：`artifacts/kuanggu_bridge_ref.wav`。
- 定位：这是**参考音频**，不是 FPGA 演示曲；赛题禁止直接播放预录 PCM。下一步是把它转写成音符事件表。原曲由虚拟歌手演唱，音高比人声干净，适合逐音提取。
