// 一个独立声部：DDS 相位/波表、ADSR 包络和力度缩放；四声部由顶层并行实例化。
// 当前每声部有插值、包络、力度三处乘法，四声部综合为 12 个 MULT18X18；
// 增加声部前须重新核对 BSRAM、乘法器和时序，不能只修改顶层声部数量。
// gate 表示键仍按下，idle 表示释音已结束，两者含义不同。
module poly_voice (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    input  wire               gate,
    input  wire               start,         // one clk pulse from the allocator
    input  wire        [31:0] phase_inc,
    input  wire        [7:0]  velocity,     // 0 .. 127
    output wire signed [15:0] sample,
    output wire               idle          // envelope is back at zero
);

    wire signed [15:0] osc_sample;
    wire        [15:0] env;
    reg                start_pending;
    wire               restart_sample = gate & (start | start_pending);

    // 分配器 start 只有一个 clk，事件未必对齐音频采样点，因此暂存到 sample_tick。
    // 相位和包络在同一采样点重启；此前已松键时 gate 会阻止迟到的重启。
    // 同一采样点前的多次重按合并为一次重启；最新音高/力度由分配器寄存值提供。
    always @(posedge clk) begin
        if (rst)
            start_pending <= 1'b0;
        else if (sample_tick)
            start_pending <= 1'b0;
        else if (start)
            start_pending <= 1'b1;
    end

    dds_osc u_dds (
        .clk         (clk),
        .rst         (rst),
        .sample_tick (sample_tick),
        .retrigger   (restart_sample),
        .phase_inc   (phase_inc),
        .sample      (osc_sample)
    );

    adsr u_adsr (
        .clk         (clk),
        .rst         (rst),
        .sample_tick (sample_tick),
        .gate        (gate),
        .retrigger   (restart_sample),
        .env         (env),
        .idle        (idle)
    );

    // osc 为 signed 16 位、env 为 unsigned 16 位（0..65535）；先分别符号/零扩展。
    // 32 位 signed 乘积可容纳全范围，取 [31:16] 相当于算术除以 65536。
    wire signed [31:0] osc_ext = {{16{osc_sample[15]}}, osc_sample};
    wire signed [31:0] env_ext = {16'd0, env};
    wire signed [31:0] env_mul = osc_ext * env_ext;
    wire signed [15:0] voiced  = env_mul[31:16];

    // 上游约定 velocity=0..127；此处除以 128，最大力度为 127/128，无四舍五入。
    // 本模块未钳制 128..255，输入边界须由命令解析器/未来外设适配器负责。
    wire signed [31:0] vel_mul = voiced * $signed({1'b0, velocity});

    assign sample = vel_mul[22:7];

endmodule
