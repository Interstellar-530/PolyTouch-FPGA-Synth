# 2026-10-30 快速延音踏板 Flash 写入

按用户明确指令“烧录到flash”，将v0.7刚验证的相同位流写入Flash，SHA256为b4dd1b5d1a5d89ba871e34f4e230a85fbe3c92c486934f57dcc811bdb2edf003。不改源码、不重新构建、不重复运行仿真。

Programmer operation37完成擦除、写入及内置校验，100%、Program and Verify flash successfully、退出0。operation1重载成功；立即读码尚未就绪，等待稳定后再次operation0读码，ID0x0000081B、User Code0x00002626、Status0x00006020，退出0。第一次未匹配记录保留，没有重复擦写。

Flash已更新且重载核对通过。彻底断电冷启动、踏板实物响应和听感待现场确认。归档archive/FPGA-20261030-v0.8，保留源码、位流、复现命令、完整操作证据和SHA256；无临时目录待清理。回退需重新写入旧Flash位流，断电不会自动恢复旧版本。
