// 27 MHz 标准 I2S 档：核心板板载 27 MHz 有源晶振（H11，GCLKT_0）作系统时钟。
// 派生频率：BCK = clk/9 = 3.000 MHz（高 4 拍、低 5 拍），每帧 64 个 BCK，
// LRCK = clk/576 = 46.875 kHz；三线输出由系统时钟使能产生；接口使用路径上界加显式半周期预算。
// 27 MHz 无法用整数分频得到精确 48 kHz（49.152/27 = 2048/1125），所以本档是
// 46.875 kHz 的替代档；12.288 MHz 档见 constraints/primer20k_i2s.sdc。
// UART 分频为 234 拍/位（115200 目标，实际 115 384，误差 0.16%）。
create_clock -name clk_27m -period 37.037 [get_ports {clk_27m}]

# Interface route envelopes, ns. These are NOT device setup/hold declarations.
# Verified together with docs/hardware/standard27-interface-budget-20261023.md.
# No false paths/multicycle exceptions are used to hide peripheral paths.
set_max_delay 20 -to [get_ports {i2s_bck i2s_lrck i2s_din adc_cs_n adc_sck adc_mosi}]
set_min_delay 0 -to [get_ports {i2s_bck i2s_lrck i2s_din adc_cs_n adc_sck adc_mosi}]
set_max_delay 20 -from [get_ports {adc_miso}]
