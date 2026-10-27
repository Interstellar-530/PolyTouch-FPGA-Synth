// 调试档：板载 27 MHz 晶振（H11）作系统时钟。
// PT8211 的 BCK 由 27 MHz 分频得到（18 拍/BCK = 1.5 MHz），采样节拍 27e6/576 = 46.875 kHz。
// 标准 I2S 档是另一份约束 constraints/primer20k_i2s.sdc（12.288 MHz），
// 两档点流互斥、各自对应 build/isolated/ 下的一个薄封装，因此这里不出现 12.288 MHz 端口。
create_clock -name clk_27m -period 37.037 [get_ports {clk_27m}]
