# 调试日志：循环飞快的根因与修复（2026-10-10 修订十六）

## 现象

循环标记灯闪烁间隔只有零点几秒，而标称值是 32.5 到 130 秒；曲子听上去是飞快地重复一小段。前两轮把速度调慢都没有改善听感。

## 方法：改成仿真定位

继续靠读代码推理已经不够了，于是本机安装了 Icarus Verilog，直接对 RTL 做仿真，而不是对金模型做仿真。写了两个测试台：一个量 PT8211 发送器给出的采样节拍周期，一个量播放器走完一圈需要多少个采样节拍，并跟踪播放器内部状态。

## 第一个结论：采样节拍是对的

`tb_tick_rate.v` 实测 `sample_tick` 每 576 个 27 MHz 时钟出现一次，与 1.5 MHz 的 BCK 除以 32 完全吻合，即 46875 Hz。因此音高是准的，音频接口本身没有问题，"混叠"的怀疑至此可以排除。

## 第二个结论：找到根因

`tb_song_timing.v` 打印播放器内部状态时，出现了连续四条"同一采样节拍上的 tick_pulse"：

```
pulse 1 at tick 19535: mel_idx 40 mel_left 0 gap_len 1 bactive 0
pulse 2 at tick 19535: mel_idx 0  mel_left 3 gap_len 1 bactive 1
pulse 3 at tick 19535: mel_idx 0  mel_left 3 gap_len 1 bactive 1
pulse 4 at tick 19535: mel_idx 0  mel_left 3 gap_len 1 bactive 1
```

仿真的采样节拍是每 4 个时钟一次，所以这里看到 4 条；换成真实硬件就是每 576 个时钟一次，也就是 576 条。问题出在节拍计数器的写法：

```verilog
wire tick_pulse = (tick_cnt == tick_top);
always @(posedge clk)
    if (rst)          tick_cnt <= 16'd0;
    else if (sample_tick)
        tick_cnt <= tick_pulse ? 16'd0 : tick_cnt + 16'd1;
```

`tick_cnt` 只在 `sample_tick` 到来时才加一，所以它到达 `tick_top` 后会保持这个值，直到下一个 `sample_tick` 把它清零，也就是保持整整一个采样节拍。于是 `tick_pulse` 是一个宽 576 个时钟的电平，而不是单周期脉冲。

播放器是按单周期脉冲来用它的：一次事件突发占 8 个时钟，突发结束后 `tick_pulse` 仍然为高，`else if (tick_pulse)` 分支就在这个节拍剩下的约 570 个时钟里把音符时值计数器连续减掉几百次，旋律于是一次又一圈地跑完。实测循环落在零点几秒，与现象吻合。

这同时解释了此前两轮降速为什么没有效果：调整的是节拍周期，也就是两次狂奔之间的空档长度，狂奔本身没有改变，所以听上去"依然很快"。

## 修复

```verilog
wire tick_pulse = sample_tick && (tick_cnt == tick_top);
```

用 `sample_tick` 限定之后，`tick_pulse` 恰好一个时钟宽。

## 复验

修复后重跑仿真：两圈之间的间隔是 3046992 个采样节拍，与标称的 156 单位乘 9766 乘 2 倍一致，换算成时间正好 65.0 秒；一圈内共 68 个音符事件，等于 41 个旋律音加 27 个和弦音，与设计一致。逐条核对音符间距：第一个音到第二个音是 3 个单位（发声 2 加气口 1），第六个音是 7 个单位（发声 6 加气口 1），都与数据表吻合。

构建无警告，资源 4588 逻辑单元、786 寄存器、4 块 BSRAM、6 个 DSP，码流 SHA256 `d295a3169d55d8634bd2034f94aab322b401a8dd837df447c429ad25e758c2e9`，User Code `0x0000EC2E`，已写入 SRAM 并回读确认。

## 教训

这类"电平当脉冲用"的问题，读代码时看起来完全正常，因为表达式的形式很自然；只有在仿真里把信号逐周期打出来才会暴露。以后凡是把某个使能当单周期脉冲使用的地方，都要确认它的产生方式与采样节拍的宽度无关。

## 环境变更

本机通过 winget 安装了 Icarus Verilog 12.2022.06.11（`C:\iverilog`），用于 RTL 仿真。它是开发期工具，不参与硬件运行；仿真产物 `*.vvp` 已加入 `.gitignore`。
