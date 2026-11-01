// 标准 I2S 档：外部 12.288 MHz 有源晶振（T7，J14-10，GCLKT_3）作系统时钟。
// 派生频率：BCK = clk/4 = 3.072 MHz，每帧 64 个 BCK，LRCK = clk/256 = 48 kHz；
// 三线输出与全部逻辑同域、由同一时钟分频得到，不需要生成时钟约束。
// UART 分频为 107 拍/位（115200 目标，实际 114 841，误差 0.31%，在容许范围内）。
// 调试档是另一份约束 constraints/primer20k.sdc（27 MHz），两档点流互斥。
create_clock -name clk_12m288 -period 81.380 [get_ports {clk_12m288}]
