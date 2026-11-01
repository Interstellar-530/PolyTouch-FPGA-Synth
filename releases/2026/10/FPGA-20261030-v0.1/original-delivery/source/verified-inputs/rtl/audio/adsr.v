// ADSR 的五状态实现：Idle、Attack、Decay、Sustain、Release。
// env 是 16 位无符号幅度系数（0..65535），每个 sample_tick 增减一次步长；
// 时间由步长和采样率共同决定，切换到 48 kHz 时需重新核对包络时长。
// gate=0 进入 Release，直到 env=0 才 idle；松键不会立即截断输出。
// 本版修复的关键是 Release 每个采样点继续递减，不能每次松键都重进 Release。
module adsr #(
    parameter [15:0] ATTACK_STEP   = 16'd140,
    parameter [15:0] DECAY_STEP    = 16'd16,
    parameter [15:0] RELEASE_STEP  = 16'd48,
    parameter [15:0] SUSTAIN_LEVEL = 16'd45875   // 70 percent of full scale
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_tick,
    input  wire        gate,
    input  wire        retrigger,    // sampled with sample_tick; restart a reused voice
    output reg  [15:0] env,
    output wire        idle
);

    localparam [2:0] ST_IDLE    = 3'd0;
    localparam [2:0] ST_ATTACK  = 3'd1;
    localparam [2:0] ST_DECAY   = 3'd2;
    localparam [2:0] ST_SUSTAIN = 3'd3;
    localparam [2:0] ST_RELEASE = 3'd4;

    reg [2:0] state;

    // 分配器只把 idle 视为真正空闲；gate 已低的声部仍可能处于释音尾部。
    assign idle = (state == ST_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            env   <= 16'd0;
        end else if (sample_tick) begin
            // 优先级：有效重按 > 首次松键 > 释音中重新按下 > 正常状态推进。
            // 排除 ST_RELEASE，保证 gate 保持低时不会阻断下面的释音递减。
            if (retrigger && gate) begin
                env   <= 16'd0;
                state <= ST_ATTACK;
            end else if (!gate && (state != ST_IDLE) && (state != ST_RELEASE)) begin
                state <= ST_RELEASE;
            end else if (gate && (state == ST_RELEASE)) begin
                env   <= 16'd0;
                state <= ST_ATTACK;
            end else begin
                case (state)
                    ST_IDLE: begin
                        env <= 16'd0;
                        if (gate) state <= ST_ATTACK;
                    end
                    ST_ATTACK: begin
                        if (env >= (16'hFFFF - ATTACK_STEP))
                            begin env <= 16'hFFFF; state <= ST_DECAY; end
                        else
                            env <= env + ATTACK_STEP;
                    end
                    ST_DECAY: begin
                        if (env <= (SUSTAIN_LEVEL + DECAY_STEP))
                            begin env <= SUSTAIN_LEVEL; state <= ST_SUSTAIN; end
                        else
                            env <= env - DECAY_STEP;
                    end
                    ST_SUSTAIN: begin
                        env <= SUSTAIN_LEVEL;
                        if (!gate) state <= ST_RELEASE;
                    end
                    ST_RELEASE: begin
                        if (env <= RELEASE_STEP)
                            begin env <= 16'd0; state <= ST_IDLE; end
                        else
                            env <= env - RELEASE_STEP;
                    end
                    default: begin
                        state <= ST_IDLE;
                        env   <= 16'd0;
                    end
                endcase
            end
        end
    end

endmodule
