// 单声部 DDS：32 位相位累加器 + 512 点、16 位有符号正弦表 + 线性插值。
// phase_inc = f * 2^32 / Fs；相位仅在 sample_tick 更新，32 位溢出自然回绕。
// phase[31:23] 为表地址，phase[22:14] / 512 为插值比例，低 14 位不参与查表。
// 插值减小查表量化误差，不能消除模拟电源/耳放底噪，也不等于带限波形处理；
// 高频丰富谐波的波表仍需另做抗混叠设计。本版只有固定的正弦波表。
// sample_tick 必须是单 clk 脉冲；外层音频时序负责保证各声部同步推进。
module dds_osc (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    input  wire               retrigger,    // restart the phase on a new note
    input  wire        [31:0] phase_inc,
    output reg  signed [15:0] sample
);

    reg [31:0] phase;
    reg signed [15:0] wave_rom [0:511];

    wire [8:0] idx_a = phase[31:23];
    wire [8:0] idx_b = idx_a + 9'd1;          // wraps to entry 0 at the top
    wire signed [9:0] frac = {1'b0, phase[22:14]};

    wire signed [15:0] ya = wave_rom[idx_a];
    wire signed [15:0] yb = wave_rom[idx_b];

    // 两个 signed 16 位样本之差需 17 位；正分数也显式声明 signed，避免混合符号。
    wire signed [16:0] diff = yb - ya;
    wire signed [26:0] prod = diff * frac;    // both operands signed on purpose

    // 加半个 LSB 后算术右移 9 位，恢复样本尺度；中间位宽保留差值和乘积范围。
    wire signed [17:0] corr = (prod + 27'sd256) >>> 9;
    wire signed [18:0] interp = ya + corr;

    initial begin
        // 仿真/综合从工程工作目录读取初始化文件；当前综合报告映射为 pROM。
        // 资源结果须以综合报告核对，扩展波表时应改用 Gowin BSRAM ROM IP/原语，
        // 不能把大型波表改写成 case。此处在本次发布中保持现有实现不变。
        $readmemh("rtl/audio/wave_sine.hex", wave_rom);
    end

    always @(posedge clk) begin
        if (rst) begin
            phase <= 32'd0;
            sample <= 16'sd0;
        end else begin
            if (sample_tick) begin
                if (retrigger)
                    phase <= 32'd0;
                else
                    phase <= phase + phase_inc;
            end

            // 每 clk 寄存查表/插值结果，切断到 poly_voice 包络乘法的组合路径。
            // 非阻塞赋值读取旧 phase：重启/步进后的相位在下一 clk 反映到 sample。
            sample <= interp[15:0];
        end
    end

endmodule
