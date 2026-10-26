# A 线共同基线核对（2026-10-24）

HEAD: 67a9aaf7a98a51e991be760badc0b3177f40fd7f（分支 codex/v2.1.1-integration-20261022，工作区 dirty）

下表为开工前当前工作区的 SHA256，与 `archive/FPGA-20261023-v0.8` 及基线审计逐条一致：

| 文件 | SHA256 |
|---|---|
| `rtl/prototypes/voice_sched32.v` | `243a7d30c8cb2a1628a92a0f18c52cd428a8560b1fcb173465083a7d52ab9157` |
| `rtl/prototypes/ram32_clocked_top.v` | `7972b72d9d57abb8abf2715ddd7e3c06f5c57af10d0472c280a3735931ac3c32` |
| `rtl/prototypes/ram32_control_front.v` | `381a6d8c674dc7bd6ff420fc18485d4743f293a10621e9cf907e89286ff67d73` |
| `rtl/prototypes/instrument_ram_audio_compute.v` | `14de76657af3268a6e356915e51be4635cd53a3fff5baf2484d8382b2534ac0f` |
| `rtl/prototypes/instrument_ram_wavetable_engine.v` | `d2b7bf75f515dbb5269abf84918ac3e706c913ebffd5087d5a625455a7098dae` |
| `rtl/audio/wide_master.v` | `c8f1da8ede712f9613c42f0b2f683903cbf058b9c9911c7a7dcb786b548db3ee` |
| `rtl/audio/audio_frame_bridge_stereo.v` | `9636a4e8d8d8bf6cadd56ae08f46b073bf7298869bc4610f30923c898945afae` |
| `sim/tb_ram32_engine_audio.v` | `afb12cbfca60cd814db4cefc18c28029d9e7eb496ac43de88ed9844059fd7d14` |
| `sim/run_simulation.ps1` | `6208640f4995dfbe51eda4bc9e01ecbfebb87d4b1bf7751e5aad4ad879fdb31f` |

本轮拥有并修改：`epiano_bank_all.hex`、`guitar_bank_all.hex`、`gowin_prom_piano_bank.v`、
`gowin_prom_guitar_bank.v`、`epiano_bank_meta.json`、`guitar_bank_meta.json`（A2 数据），
`sim/run_simulation.ps1`（登记 OptA 三台测试台），新增 `sim/opt_a/` 与 `tools/offline_opt/a/`。
A1 与 A3 经分析后**未修改**任何既有 RTL：位宽余量与过渡残差均为正，改动的风险大于收益（理由见 A1/A3 文档）。
