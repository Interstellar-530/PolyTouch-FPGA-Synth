# 周末 standard27 的 Flash 写入证据

用户明确要求写 Flash 并跳过门禁。本轮未改 RTL、未重新构建或运行仿真；复用原周末 FPGA-20261024-v0.4 位流。目标 SHA256 e9341aa47674ecf90bf677024830f4de7a771e3b56384240b9c32382cc062137，193 个归档构建输入与原收据一致，见 provenance.json。

program-flash.log 明确显示操作 37、擦写完成、Program and Verify flash successfully、Finished；program-result.json 记录退出码 0 与成功判据。reload-from-flash.log 是未传位流的操作 1。device-after-reload.log 是重载 2 秒后未就绪的初始记录；device-after-ready.log 是延后读到 0x000063DC / 0x00006020 的记录，reload-result.json 汇总最终结果。

本次成功范围是 Flash 擦写校验和从 Flash 重配置启动。未做彻底断电冷启动或串口、实际音频和键盘验收。归档及回退见 archive/FPGA-20261026-v0.1。本轮没有运行临时构建；缓存清理范围和结果见 cleanup-result.json。
