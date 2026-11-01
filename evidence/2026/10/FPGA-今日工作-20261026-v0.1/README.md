# 今日成果证据

release-check 是本次仅含本对话修改的发布源码检查，输入哈希绑定为发布基线 b656b0d 加明确的键盘/测试文件，不包含其他智能体尚未提交的曲目修改。

historical-keyboard 为此前 v0.8 冻结工作区的证据，该快照含当时的其他曲目修改；build-result.json 对应的位流没有烧录。latency 为 v0.9 核心仿真结果。plan 是纯理论预算及复算脚本，不能解释为实测。

本次仅推送独立分支，未切换当前工作分支，未使用共享暂存区，未清理其他任务文件。完整本地归档不进入 Git。

原始测试输入 SHA256 对应 Windows 换行快照；Git 将文本保存为 LF。release-check/source-git-normalization.json 逐文件核对这类差异，只接受 CRLF/LF 转换，不接受代码内容变化。原始日志及证据通过本目录 .gitattributes 保留字节，checksums.sha256 可直接核对。
