# PuTTY 串口工具

使用官方 PuTTY 0.85（MIT 许可证），Windows x64 独立可执行文件，无需额外运行库。图形工具与 Plink 位于 `../vendor/putty-0.85/`，属于保留的运行时工具，不是临时文件；vendor 已由仓库忽略。首次安装或重新获取时运行 `./install.ps1`，脚本只从官方站下载并校验固定 SHA256。

双击 `open-serial.cmd` 打开 COM13，参数为 115200、8 数据位、无校验、1 停止位、无流控。输入 `M0` 后按 Enter 静音，输入 `M1` 后按 Enter 恢复。`N69` 触发 A4，`O69` 松键，`X` 清除声部。N/O/X 会切换到手动模式，停止演示曲；`D0` 可显式进入手动模式，`D1` 清除当前声部并从头播放演示曲。固件会回复 `OK`；非法命令回复 `ERR`。使用自动命令前先关闭图形串口窗口，避免端口占用。

PowerShell 单次命令示例：

```powershell
& .\tools\putty\send-command.ps1 -Port COM13 -Command M0
& .\tools\putty\send-command.ps1 -Port COM13 -Command M1
& .\tools\putty\send-command.ps1 -Port COM13 -Command D1
```

脚本调用新安装的 `plink.exe`，等待设备应答，超时或非 `OK` 时抛出错误，最后关闭自己启动的 Plink 以释放串口。静音只持续到复位或断电，Flash 内的《兰花草》测程默认上电解除静音并自动播放。

来源：[官方发布页](https://www.chiark.greenend.org.uk/~sgtatham/putty/releases/0.85.html)、[串口命令说明](https://the.earth.li/~sgtatham/putty/0.85/htmldoc/Chapter3.html#using-cmdline-sercfg)、[MIT 许可证](https://www.chiark.greenend.org.uk/~sgtatham/putty/licence.html)。下载的许可页面和官方 SHA256 清单保存在 vendor 目录。本轮两个程序的 Authenticode 签名均有效，签名者为 Simon Tatham。
