# 优化 02：构建内容绑定与可复现生成（2026-10-21）

对应 `docs/reviews/FPGA-Git差异与优化方向-20261021-v0.1.md` 的第 2 项。改动只涉及构建脚本、
再制表脚本和构建入口测试；RTL、约束、ROM 数据与工具链都没有变化，也没有烧录或下载任何素材。

## 原指标

- `profile_helpers.ps1` 的 `Get-BuildInputs` 只记录 `Length` 和 `ModifiedUtc`；`build.ps1` 前后两次
  指纹、`program_sram.ps1` 烧录前的指纹校验都直接比较这两个字段。等长且保留时间戳的改动不可见，
  `build/README.md` 原文也写明“时间和大小……不是内容的密码学证明”。
- 构建凭据没有工具版本，也没有位流 SHA256，只记录位流路径、长度和修改时间。
- `tools/gen_epiano_bank.py`、`gen_guitar_bank.py`、`gen_guitar_samples_bank.py` 把
  `E:\Working Space\FPGA` 写死；前两个还把 `tmp/akwf/...wav`、`tmp/karoryfer/...Samples`
  写死，换目录或换机器就无法复现。

## 优化方法

1. 输入指纹改为内容绑定。`Get-BuildInputs` 对 222 个输入（`sources.list` 的 RTL、`rtl/audio` 下
   全部 `.vh/.hex/.mi/.mif`、两份约束、构建脚本与 profile 顶层封装）逐个记 `Path/Length/Sha256`；
   新增 `Get-BuildInputsDigest`（整组输入的汇总 SHA256）和 `Test-BuildInputsUnchanged`
   （只按路径和内容比较，忽略时间戳）。
2. `build.ps1` 的前后校验改用内容比较；成功凭据新增 `BitstreamSha256`、
   `Tool{Name,Path,Version,VersionSource}`（版本从 PnR 报告的 `<Tool Version>` 读取）、
   `InputsDigest` 和每项的 `Sha256`。
3. `program_sram.ps1` 同样按内容校验；位流优先校验 SHA256，只有旧格式凭据才回退到长度/时间戳。
   旧格式凭据因此一律按“输入不一致”拒绝，需要重建一次。
4. 三个再制表脚本加 `argparse`：`--repo-root`、`--wav` / `--samples`、`--out-dir`，
   默认路径由 `__file__` 推导。普通构建使用入库 ROM/HEX，不调用再制表脚本，也无需重新下载素材；
   重新制作电钢琴波表仍需原 WAV，采样吉他波表仍需原 Samples，可通过新参数指定来源。
5. 测试分两层：
   - 新增 `build/test_build_inputs.ps1`，在临时目录里复制一份输入布局，验证“等长＋保留时间戳的
     改动被识别”“只改时间戳不被误判”“恢复字节后身份恢复”，共 11 项，不触碰被跟踪文件。
   - 扩展 `tools/verify_build_profiles.py` 到 16 项：mock `gw_sh` 额外产出 `<Tool Version>` 报告以
     验证工具版本绑定；新增“只改时间戳必须放行”“等长＋保时间戳的源码改动必须拒绝烧录”
     “构建期间发生等长改动必须中止且不写成功凭据”三项。

## 最终指标

| 检查项 | 结果 |
|---|---|
| 指纹覆盖 | 222 个输入，全部 64 位 SHA256 |
| 汇总摘要 | `InputsDigest=3f4565c0…25c095`，与当前工作树重新计算的结果一致 |
| 工具版本 | `V1.9.11.03 Education`，来源 `pnr_report` |
| 位流绑定 | `BitstreamSha256=c56fa328c18605d8…f37b49`（本次实际产物） |
| 等长＋保留时间戳的改动 | 被识别：指纹单测、烧录前校验、构建期守卫三层都拒绝 |
| 只改时间戳（内容不变） | 不误判，凭据继续可用 |
| 构建期间输入变更 | 本次构建作废，不写成功凭据 |
| 既有入库 HEX 无下载构建 | 通过（本轮真实 PnR 未下载任何素材） |
| 再制表可复现 | 电钢琴 39/39、吉他采样 39/39 个文件与入库版本逐字节一致；legacy 6 段吉他脚本 9 个文件正常产出 |
| 构建入口测试 | `verify_build_profiles.py` 16/16 通过；`test_build_inputs.ps1` 11/11 通过 |

## 资源占用对比（debug8usb，GW2A-18，gw_sh V1.9.11.03）

| 资源 | 优化前 | 优化后 | 差值 |
|---|---:|---:|---:|
| Logic | 11379 / 20736 (55%) | 11379 / 20736 (55%) | 0 |
| Register | 3686 / 16173 (23%) | 3686 / 16173 (23%) | 0 |
| BSRAM | 40 / 46 (87%) | 40 / 46 (87%) | 0 |
| DSP | 1.75 / 24（1×18×18、1×9×9、1×36×18） | 同左 | 0 |
| Fmax @ 27 MHz | 31.039 MHz | 31.039 MHz | 0 |
| 最差建立/保持裕量 | +4.820 / +0.214 ns | +4.820 / +0.214 ns | 0 |

本项只改构建侧，RTL/约束/ROM 未动，所以资源与时序应当完全相同，实测也确实相同。
位流 SHA256 与上一轮不同：`.fs` 头部自带 `Created Time` 字段（文件偏移 532 附近可见），
同一组输入的两次构建不可能逐字节相同。凭据绑定的是“本次实际产物”，可复现性以输入指纹、
资源报告和再制表结果为准，而不是 `.fs` 逐字节相等。

## 复现命令

```powershell
cd output\handoff_milestone2_20261008\source\build
.\test_build_inputs.ps1                     # 11 项，无 Gowin、无硬件
.\build.ps1 -Profile debug8usb -GwSh E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe
cd E:\Working Space\FPGA
tools\.venv-audio-analysis\Scripts\python.exe tools\verify_build_profiles.py --out tmp\build_profiles_check_20261021
powershell -File docs\evidence\FPGA-优化02-构建绑定-20261021\commands\verify_regenerated_tables.ps1
```

## 文件

- `build_scripts.patch`：`profile_helpers.ps1` / `build.ps1` / `program_sram.ps1` / `build/README.md` 的改动
- `generator_scripts.patch`：三个再制表脚本的 CLI 改动
- `build_entry_tests.patch`：`tools/verify_build_profiles.py` 的新增用例
- `test_build_inputs.ps1`、`verify_regenerated_tables.ps1`：两个自检脚本的副本
- `verify_build_profiles.log`（16 项）、`test_build_inputs.log`（11 项）
- `regen_summary.json`、`regen_epiano.log`、`regen_guitar_samples.log`
- `debug8usb.receipt.json`：新格式凭据；`metrics_after.json`：同一构建的资源与时序
- `build.log`、`build_reports/`：本次真实综合布线日志与报告
