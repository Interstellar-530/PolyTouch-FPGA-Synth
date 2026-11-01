// [S3-AI | deepseek | 2026-10-14] 标准 I2S（Philips）发送器，参数化时钟与采样率。
// [S3-REVIEW | Codex | 2026-10-14] 统一默认参数，端点常数不依赖隐式截断。
//
// 依据 TI PCM5102A 数据手册 SLAS859C：
//   §9.3.2.1  DIN 在 BCK 上升沿被锁入器件，所以本模块在 BCK 下降沿更新 DIN/LRCK。
//   §9.3.2.2  FMT 低选标准 I2S；二进制补码、MSB 在前，16/24 位均可配 64 BCK/帧（表 2）。
//   图 14     标准 I2S 下 L 声道 = LRCK 低、R 声道 = LRCK 高，
//             新声道 MSB 比 LRCK 切换晚一个 BCK（位置 0 是零延迟位）。
//   §9.3.5.3  三线模式下 48 kHz 对应 3.072 MHz BCK（表 11），SCK 保持低电平由内部 PLL 生成。
//
// 分频是整数计数器，不是相位累加器，也不派生内部时钟域：所有状态都在 posedge clk 更新。
//   FRAME_CYC = CLK_HZ / SAMPLE_RATE_HZ     每帧（一个 LRCK 周期）的系统拍数
//   BCK_CYC   = FRAME_CYC / 64              一个 BCK 周期的拍数
//   高电平 BCK_HIGH_CYC = BCK_CYC/2 拍，低电平 BCK_LOW_CYC = BCK_CYC - BCK_HIGH_CYC 拍
// 标准档为 256/4/2/2 拍，调试档为 576/9/4/5 拍。奇数分频时固定高电平短一拍、低电平长一拍，
// 完整 BCK 周期恒定，因此没有逐周期长度抖动，只有 4:5 的占空比差异。
//
// 启动顺序（E0/E1）：复位释放后第一次真实的 LRCK 高→低边界是 E0。到 E0 之前的残段和
// E0 之后的第一个完整左右帧都强制发零，即使输入已经非零；E0 发出第一个 sample_tick；
// 从 E1（下一次 LRCK 高→低）起正常同时锁存左右输入。
//
// 抗撕裂：每个正常帧边界只锁存一次左右样本（左半帧直接用边界值，右半帧用同一拍的 hold_r），
// 因此帧中途改变输入只影响下一帧。硬复位会清分频/槽状态、保持寄存器和 tick，三线输出为 0；
// 运行中的数字静音应当把左右输入置零，不要拉高 rst。
`include "rtl/audio/clk_params.vh"
module i2s_tx #(
    parameter integer CLK_HZ         = `FPGA_AUDIO_STD_CLK_HZ,
    parameter integer SAMPLE_RATE_HZ = `FPGA_AUDIO_STD_FS_HZ,
    parameter integer DATA_BITS      = 16          // 每声道有效位数，只支持 16 或 24
)(
    input  wire                        clk,
    input  wire                        rst,
    input  wire signed [DATA_BITS-1:0] sample_l,
    input  wire signed [DATA_BITS-1:0] sample_r,
    output reg                         bck,
    output reg                         lrck,
    output reg                         din,
    output reg                         sample_tick
);

    // ---------------------------------------------------- 协议常量与派生参数 ---
    localparam integer SLOTS_PER_FRAME = `FPGA_AUDIO_SLOTS_PER_FRAME;
    localparam integer SLOTS_PER_HALF  = 32;   // 每声道槽数
    localparam integer SLOT_BITS       = 6;    // 槽计数器 0..63
    localparam integer POS_BITS        = 5;    // 声道内位置 0..31

    // 涉及除法的派生量先做零分母保护，让非法配置进入诊断而不是展开期错误。
    localparam integer FRAME_CYC_RAW = (SAMPLE_RATE_HZ > 0) ? (CLK_HZ / SAMPLE_RATE_HZ) : 0;
    localparam integer FRAME_OK      = (CLK_HZ > 0) && (SAMPLE_RATE_HZ > 0) &&
                                       (CLK_HZ % SAMPLE_RATE_HZ == 0) &&
                                       (FRAME_CYC_RAW % SLOTS_PER_FRAME == 0);
    localparam integer FRAME_CYC     = FRAME_OK ? FRAME_CYC_RAW : 256;   // 非法时的安全占位
    localparam integer BCK_CYC_RAW   = FRAME_CYC / SLOTS_PER_FRAME;
    localparam integer BCK_OK        = (BCK_CYC_RAW >= 2);
    localparam integer BCK_CYC       = BCK_OK ? BCK_CYC_RAW : 4;         // 非法时的安全占位
    localparam integer BCK_HIGH_CYC  = BCK_CYC / 2;
    localparam integer BCK_LOW_CYC   = BCK_CYC - BCK_HIGH_CYC;
    localparam integer DATA_BITS_OK  = (DATA_BITS == 16) || (DATA_BITS == 24);

    // 计数器位宽至少 1 位，避免 $clog2(1) 那样的零宽寄存器。
    function integer bits_for;
        input integer value;
        begin
            bits_for = 1;
            while ((1 << bits_for) < value)
                bits_for = bits_for + 1;
        end
    endfunction

    localparam integer BCK_CNT_BITS = bits_for(BCK_CYC);
    // BCK_CYC 是 2 的幂时可能超出计数器宽度；保存实际末值，避免截断成零。
    localparam [BCK_CNT_BITS-1:0] BCK_LAST_C     = BCK_CYC - 1;
    localparam [BCK_CNT_BITS-1:0] BCK_HIGH_CYC_C = BCK_HIGH_CYC;

`ifdef SIMULATION
    // 参数合法性只在仿真里检查；综合时这段被排除，同一参数配置另有隔离综合入口。
    initial begin
        if (SAMPLE_RATE_HZ <= 0) begin
            $display("S3_PARAM_INVALID: SAMPLE_RATE_HZ=%0d 必须大于 0", SAMPLE_RATE_HZ);
            $fatal(1, "S3_PARAM_INVALID: SAMPLE_RATE_HZ must be greater than 0");
        end else if (CLK_HZ <= 0) begin
            $display("S3_PARAM_INVALID: CLK_HZ=%0d 必须大于 0", CLK_HZ);
            $fatal(1, "S3_PARAM_INVALID: CLK_HZ must be greater than 0");
        end else if (CLK_HZ % SAMPLE_RATE_HZ != 0) begin
            $display("S3_PARAM_INVALID: CLK_HZ=%0d 不能被 SAMPLE_RATE_HZ=%0d 整除（每帧 %0d.%0d 拍）",
                     CLK_HZ, SAMPLE_RATE_HZ, CLK_HZ / SAMPLE_RATE_HZ,
                     ((CLK_HZ * 10) / SAMPLE_RATE_HZ) % 10);
            $fatal(1, "S3_PARAM_INVALID: CLK_HZ not divisible by SAMPLE_RATE_HZ");
        end else if (FRAME_CYC_RAW % SLOTS_PER_FRAME != 0) begin
            $display("S3_PARAM_INVALID: 每帧 %0d 拍不能被 64 个 BCK 整除", FRAME_CYC_RAW);
            $fatal(1, "S3_PARAM_INVALID: FRAME_CYC not divisible by 64");
        end else if (BCK_CYC_RAW < 2) begin
            $display("S3_PARAM_INVALID: BCK 周期只有 %0d 个系统拍，至少需要 2 拍", BCK_CYC_RAW);
            $fatal(1, "S3_PARAM_INVALID: BCK_CYC must be at least 2");
        end else if (!DATA_BITS_OK) begin
            $display("S3_PARAM_INVALID: DATA_BITS=%0d 只支持 16 或 24", DATA_BITS);
            $fatal(1, "S3_PARAM_INVALID: DATA_BITS must be 16 or 24");
        end
    end
`endif

    reg [BCK_CNT_BITS-1:0] bck_cnt;    // 0..BCK_CYC-1
    reg [SLOT_BITS-1:0]    slot;       // 0..31 左声道，32..63 右声道
    reg [DATA_BITS:0]      sr;         // {待发数据位, 1'b0}，最高位是下一次送出的位
    reg signed [DATA_BITS-1:0] hold_r;
    reg [1:0]              data_state; // 0 等 E0；1 E0..E1 强制零；2 正常运行

    // 本拍结束时的 BCK 计数器值与电平；翻转事件由计数器端点给出。
    wire [BCK_CNT_BITS-1:0] bck_cnt_next = (bck_cnt == BCK_LAST_C) ? {BCK_CNT_BITS{1'b0}}
                                                                        : (bck_cnt + 1'b1);
    wire bck_fall_now = (bck_cnt_next == BCK_HIGH_CYC_C);                // 下一拍 BCK 变低

    wire [SLOT_BITS-1:0] slot_next  = slot + 1'b1;
    wire                 right_half = slot_next[5];
    wire                 half_start = (slot_next[4:0] == 5'd0);
    wire                 frame_start = half_start && !right_half;
    // 帧边界之后应当是数据帧：E0 边界不锁存（该帧强制零），E1 及以后锁存。
    wire                 latch_now  = (data_state != 2'd0);

    always @(posedge clk) begin
        if (rst) begin
            // 释放后的第一拍开始完整高半周期；复位时的低段不参与稳态脉宽验收。
            bck_cnt     <= BCK_LAST_C;
            slot        <= {SLOT_BITS{1'b0}};
            sr          <= {(DATA_BITS+1){1'b0}};
            hold_r      <= {DATA_BITS{1'b0}};
            bck         <= 1'b0;
            din         <= 1'b0;
            lrck        <= 1'b0;
            sample_tick <= 1'b0;
            data_state  <= 2'd0;
        end else begin
            sample_tick <= 1'b0;
            bck_cnt     <= bck_cnt_next;
            bck         <= (bck_cnt_next < BCK_HIGH_CYC_C);

            if (bck_fall_now) begin
                // 稳态 DIN/LRCK 只在 BCK 下降沿改变，LRCK 由槽的声道位给出。
                slot <= slot_next;
                lrck <= slot_next[5];

                if (half_start) begin
                    din <= 1'b0;                                    // 位置 0：零延迟位
                    sr  <= latch_now ? (right_half ? {hold_r, 1'b0} : {sample_l, 1'b0})
                                     : {(DATA_BITS+1){1'b0}};
                end else begin
                    din <= sr[DATA_BITS];                           // 位置 1..DATA_BITS：MSB 在前
                    sr  <= {sr[DATA_BITS-1:0], 1'b0};
                end

                if (frame_start) begin
                    sample_tick <= 1'b1;
                    if (data_state == 2'd0) begin
                        data_state <= 2'd1;                          // E0：本帧强制发零
                    end else begin
                        data_state <= 2'd2;
                        // 左样本在本边界进入 sr，右样本同拍保持到右半帧。
                        hold_r     <= sample_r;
                    end
                end
            end
        end
    end

endmodule
