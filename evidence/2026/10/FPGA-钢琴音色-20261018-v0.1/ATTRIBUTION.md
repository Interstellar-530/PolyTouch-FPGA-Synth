# 音色数据来源与署名

频谱分析输入为 **Salamander Grand Piano v3, C1–C6 soft/loud velocity samples**。

- 作者：Alexander Holm
- 许可证：Creative Commons Attribution 3.0 Unported（CC BY 3.0）
- 项目地址：https://github.com/tambien/Piano
- 原始音色库：https://github.com/sfzinstruments/SalamanderGrandPiano
- 许可证地址：https://creativecommons.org/licenses/by/3.0/

本工程只从 C1v1/C1v16 … C6v1/C6v16 样本提取各时间窗的前 10 次谐波相对幅度和共同相位，并重新生成 72 张 512 点单周期波表。原始录音 OGG/PCM 不进入 FPGA 位流，也不随本工程发布。提取脚本为 `tools/extract_piano_spectra_20261018.py`，结果数据为 `piano-spectra.json`。

本次分析输入校验：

```
C1v1/C1v16 … C6v1/C6v16 的 SHA256 记录在 `piano-spectra.json` 的 `source.files` 字段中。
```
