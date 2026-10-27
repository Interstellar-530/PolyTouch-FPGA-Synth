// 27 MHz 标准 I2S 档：核心板板载 27 MHz 有源晶振（H11，GCLKT_0）作系统时钟。
// 派生频率：BCK = clk/9 = 3.000 MHz（高 4 拍、低 5 拍），每帧 64 个 BCK，
// LRCK = clk/576 = 46.875 kHz；三线输出与全部逻辑同域，不需要生成时钟约束。
// 27 MHz 无法用整数分频得到精确 48 kHz（49.152/27 = 2048/1125），所以本档是
// 46.875 kHz 的替代档；12.288 MHz 档见 constraints/primer20k_i2s.sdc。
// UART 分频为 234 拍/位（115200 目标，实际 115 384，误差 0.16%）。
create_clock -name clk_27m -period 37.037 [get_ports {clk_27m}]
