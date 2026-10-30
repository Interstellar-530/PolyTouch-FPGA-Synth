# MANIFEST

source/verified-inputs：成功HDMI构建的原始源码、ROM、约束、脚本及关键测试台，共230个文件；对应evidence/build/hdmi.json。source/generate_figures.py与render_figures.cjs：五款图稿的可复现生成与渲染脚本。source/verify_release.py：本包完整性及证据绑定检查。

target：10个PNG/SVG图稿与1个实际烧录位流。evidence/rtl：最终7项定向自检和真实生产顶层的结果及运行日志。evidence/ui：文字修复前后真实RTL图、像素核对、严格超时通过和修复前误清音失败记录。evidence/build：成功构建收据、资源/时序报告和仿真复用核验。evidence/sram与flash：下载、校验、重载与配置标识结果。

evidence/layout-check.json及competition-check.md：图稿边界检查与赛题对应。README、REPRODUCE和CHANGES：说明、命令、范围及回退。checksums.sha256：包内除校验文件自身之外全部文件的SHA256。所有文件保持原始字节，不随Git换行配置转换。
