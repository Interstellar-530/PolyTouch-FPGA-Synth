# 路径迁移

完整旧路径、新路径与迁移前 SHA256 见 [原始文件清单](../../evidence/2026/11/FPGA-20261101-reorganization-v0.1/original-files.json)，[路径映射](../../evidence/2026/11/FPGA-20261101-reorganization-v0.1/path-map.json)。

证据、发布包、历史实验的原字节和原绝对路径保持不变，历史命令在原提交的独立工作树中执行。当前命令使用根目录 source。原路径下忽略的 Gowin 实现目录、构建收据和工具环境留在本机，不作为当前构建凭据复用。新构建必须在新路径生成新的收据；本次不烧录、不修改 FPGA。
