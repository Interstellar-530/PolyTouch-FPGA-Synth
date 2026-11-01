# 2026-10-29 HDMI SRAM 烧录记录

合并内容：1024x600 UI + FPGA-20261029-v0.4 均衡钢琴 ROM 与 Q8 高音增益。

按用户本轮明确要求直接烧录；未执行 Quick 门禁。Icarus 编译器在本机对独立最小探针也以 -1073741819 异常退出，仿真器不可用。使用 program_sram.ps1 的 -SkipSimulation 例外，仅下载 SRAM，不写 Flash。

位流 SHA256：eadbd24eee313080541cd4d7f1b8e3020a443048ae2b65dd0c7de2e94edcb4c3
位流路径：E:\Working Space\FPGA\source\build\gowin_top_hdmi\runs\20261029T193613423-863151bf\instrument\impl\pnr\instrument.fs


## 烧录输出
退出码：1
```text
Programmer : E:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe
Device     : GW2A-18C
Operation  : 2
Bitstream  : E:\Working Space\FPGA\source\build\gowin_top_hdmi\runs\20261029T193613423-863151bf\instrument\impl\pnr\instrument.fs
Traceback (most recent call last):
  File "C:\Users\fzq\Desktop\newtimes\src\programmer_cli.py", line 13, in <module>
PermissionError: [WinError 5] 拒绝访问。: 'E:\\Gowin\\Gowin_V1.9.11.03_Education_x64\\Programmer\\bin'
```

## 直接调用 Programmer 的结果

在沙箱外执行 SRAM Program（operation 2），设备 GW2A-18C，返回码 50，提示 `Cable failed to open via the channel`，没有进入写入进度。`--scan-cables` 列出 USB Debugger A 的 0/1 两个通道，但两个通道的只读 Read Device Codes 也均提示同样的通道打开失败。未烧录成功；须恢复 Dock USB-JTAG 连接/释放占用后重试。此次没有写 Flash。

合并版构建资源：BSRAM 30/46、MULT18X18 5；像素时钟实际 Fmax 59.562 MHz，计算时钟 58.936 MHz，均高于各自 51.3/54 MHz 约束。Icarus 门禁未通过，依据前述仿真器故障和用户本轮要求按项目例外跳过。

## 重新扫描（用户确认已连接供电后）

Gowin `--scan-cables` 无线缆，退出码 48。Windows `Get-PnpDevice -PresentOnly` 没有 Gowin、FTDI 或 JTAG 设备；USB 列表有 `未知 USB 设备(设备描述符请求失败)`，状态 Error，实例 `USB\VID_0000&PID_0002\6&726CB1A&0&1`。这不能确定该未知设备就是 FPGA Dock，但表明当前 JTAG 设备未被系统正常枚举。等待用户重插 Dock USB-JTAG 数据线后重扫；尚未写入 SRAM。

## 重插后复扫

Gowin `--scan-cables` 仍无线缆，退出码 48。Windows 仍显示 `未知 USB 设备(设备描述符请求失败)`，实例 `USB\VID_0000&PID_0002\5&1423ACB5&0&3`；实例位置与上次不同，但未枚举出可用 JTAG。等待更换数据线或 USB 口。位流保持归档，未烧录。

## 2026-10-29 重新连接后烧录成功

更换 USB 连接后，`--scan-cables` 找到 USB Debugger A 两个通道（USB location 561/562）。使用 `USB Debugger A --cable-index 1`，先读得器件 ID `0x0000081B`、旧 User Code `0x0000ACF2`。对合并位流执行 `SRAM Program`（operation 2），进度达到 100%，程序退出码 0，输出新 User Code `0x00001113`、Status Code `0x00006020`。随后独立执行 `Read Device Codes`，再读得器件 ID `0x0000081B`、User Code `0x00001113`、Status Code `0x00006020`。已写入 SRAM，未写 Flash；断电后配置会丢失。音色听感和 1024x600 屏幕布局未作现场观察验收。

## 本轮波形点阵与丰富编配版本

用户要求用振动波形/点阵替换相位图，扩展测试曲到可展示8–16声部，并明确“跳过所有验证直接烧录”。本轮不执行RTL仿真、试听或独立读回；当前Icarus环境上一轮最小探针也异常退出。构建成功后直接执行SRAM Program，保持Flash不变。显示使用真实音频快照和自动显示增益，实际声部mask驱动32格活动窗。编配采用已保留的FPGA-20261029-v0.5事件ROM，归档离线数据为同时持键峰值10/11、计入释音峰值约15；这些是此前离线结果，本轮未复测。

本轮第一次构建因347条网络未布通失败，收紧波形数据与绘图逻辑后第二次构建成功。运行目录20261029T195752248-3e9e41ef。按要求直接SRAM Program返回50，随后scan-cables返回48且未发现线缆；等待重新连接后重试。未运行仿真、试听或独立读回。

本轮重插USB后直接重试SRAM Program成功：100%，Finished，退出码0。Programmer输出User Code 0x00001352，Status Code 0x00006020。未进行独立读回；未写Flash，SRAM配置断电丢失。

## 波形降速与Flash更新（v0.9）

用户要求波形减速后写入Flash。32声部生产路径WAVE_HOLD_WINDOWS设为4，波形快照约45.776Hz降到11.444Hz（每87.38ms更新）；保持采样间隔、音频速度和状态刷新。延续本轮用户明确跳过所有验证的要求，且此前已记录Icarus最小探针异常，本次不运行仿真和试听。已同步更新自检测试台但未执行。构建后使用项目已采用的Flash operation37（写入及内置校验），再执行operation1重载以使新Flash配置生效。

v0.9构建完成。首次operation37在默认2.5MHz JTAG时擦除扇区124失败，工具错误退出但进程返回0，因此未以返回码单独判成功。随后以1MHz重试operation37，输出“Program and Verify flash successfully.”及Finished，进程退出0；operation1从Flash重载成功、退出0。未另做独立读回、冷断电测试、仿真或实屏观感验证。当前成功构建目录保留供收据引用；本轮无一次性脚本、仿真缓存或待清理临时目录。
