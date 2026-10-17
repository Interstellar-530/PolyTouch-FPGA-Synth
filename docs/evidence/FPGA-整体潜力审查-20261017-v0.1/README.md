# 整体潜力审查证据

生产基线为 `4512edff7c4992053db293439ff6240f37368378`，本轮未修改生产 RTL。`tools/audit_system_ceiling.py` 为统一复现脚本，依赖现有 Icarus 和 numpy。完整报告位于 `docs/reviews/FPGA-整体潜力审查-20261017-v0.1.md`。

`ceiling.csv` 是七组音高条件、每组 8192 帧的实际共享引擎及混音 RTL 输出，包含相位、分量和、最终样本。脚本独立重算并断言全部 57344 帧一致。`simulation.log` 保存运行日志，`tb_ceiling.v` 是当次生成测试台。

`metrics.json` 中 `pitch_cases` 的越奈奎斯特能量按当前源表 FFT 计算，用于估计混叠风险；`precision_model` 是逐级定点公式的正弦残差模型；`schedule_lower_bounds` 是延用当前核心的调度算术下界。后两者及源表谱分析均不应标作模拟输出实测。

`control-probe` 包含真实 top 和引脚级 ADC 模型的一笔压力毛刺、弯音交替码探针。运行通过表示成功重现现有问题：一笔满幅毛刺使滤波峰值达到 3071；弯音2047/2049使比例65532/65540交替。这里不是抗毛刺合格证据。`reproduction.json` 保存第一次原始命令；现在可用统一脚本的 `--control-only` 参数复现，临时编译路径会重新建立。

本轮没有完整门禁、布局布线、功耗测量或硬件烧录，也没有新增外部代码依赖。
