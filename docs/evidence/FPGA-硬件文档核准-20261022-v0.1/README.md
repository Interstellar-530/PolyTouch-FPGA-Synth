# 硬件文档核准证据

日期：2026-10-22。依据硬件交叉核查，将远端 881a11c 的两份文档重整为 v0.2，并保留 v0.1 重定向入口；README 和周末计划同步入口与烧录门禁。当前工作基线为集成分支 42a3058，长按修复 4536e07 未合入。

本次范围为 Markdown 和核准证据，没有修改 RTL、CST、构建脚本、位流或外部接口。未进行硬件测量、重新 PnR、RTL 仿真或烧录，不把文档检查称为整机验收。

`verify_documents.py` 复核本次文件的相对链接、源码中的 standard27 参数及 CST 映射，并输出文档与关键依据 SHA256。`verification.json` 保存执行结果与代码基线。原厂图像已在上轮核查中视觉确认，来源见交叉核查报告；WCH 第 6/7 页、原始远端文档及相关聊天决定保存在本地前序归档，不将整份聊天记录上传仓库。

在仓库根运行：

```powershell
& '.\tools\.venv-docconvert\Scripts\python.exe' -B '.\docs\evidence\FPGA-硬件文档核准-20261022-v0.1\verify_documents.py'
```

本地交付另存 `archive/FPGA-20261022-v0.4`，含修订前来源、修订后文档、核准证据、复现说明、变更记录、MANIFEST 和 SHA256；archive 依项目规则不推送。GitHub 上直接读取本目录和 docs/hardware 的 v0.2 即可。

回退通过撤回本次文档提交；无须改硬件或恢复位流。任务没有创建临时构建/渲染目录，运行时使用 `-B` 避免 Python 缓存，原有未跟踪位流、PDF 和报告不纳入提交。
