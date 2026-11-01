# 复现

完整历史工程：`git worktree add --detach <单独目录> e8450a5b4db3095fec2a6ee0a5cb739e4ce0c43a`。

按原版 README 与工具版本构建；旧生产入口为 `output/handoff_milestone2_20261008/source`。本目录源码快照可用于阅读和比对，完整构建若依赖仓库工具或旧路径，使用独立历史工作树。

`git archive --format=zip --output=<导出文件.zip> e8450a5b4db3095fec2a6ee0a5cb739e4ce0c43a output/handoff_milestone2_20261008/source` 可重新导出原生产源码。

目标位流仅收录已存在且来源可核对的文件；未附位流表示未收录，不代表该版本已经通过构建。
