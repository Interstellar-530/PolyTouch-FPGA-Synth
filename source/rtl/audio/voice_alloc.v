// 声部分配器，当前顶层使用 VOICES=4。输入为同一 clk 域的单周期音符事件；
// 演示曲/UART 经外层事件队列与模式仲裁后共用此接口，外设扫描器尚未接入。
// Note On 依次选择：仍按住的同音声部、包络结束的空闲声部、最老释音声部、
// 最老按住声部。后两种属于声部窃取，重新启动相位/包络时可能产生瞬态。
// Note Off 关闭匹配音高的 gate，实际释音由 ADSR 完成；panic 同样走释音。
// ev_note 为 7 位 MIDI 音高，v_note/v_vel 为各声部顺序拼接的打包总线。
module voice_alloc #(
    parameter integer VOICES = 4
)(
    input  wire                clk,
    input  wire                rst,
    input  wire                ev_valid,
    input  wire                ev_on,        // 1 = note on, 0 = note off
    input  wire [6:0]          ev_note,
    input  wire [7:0]          ev_vel,
    input  wire                panic,        // release every voice
    input  wire [VOICES-1:0]   voice_idle,   // from poly_voice
    output reg  [VOICES-1:0]   v_gate,
    output reg  [VOICES*7-1:0] v_note,
    output reg  [VOICES*8-1:0] v_vel,
    output reg  [VOICES-1:0]   v_start,     // one clk pulse for each Note On
    output wire [VOICES-1:0]   v_busy
);

    // 年龄使用相对排序 0..VOICES-1（0 最新），而非随时间无限增长的计数器。
    // 每次 Note On 调整排序，长时间演奏不会因年龄计数回绕改变窃取顺序。
    localparam integer AGE_W = (VOICES < 2) ? 1 : $clog2(VOICES);
    reg [VOICES*AGE_W-1:0] v_age;

    integer k;
    integer j;
    reg [VOICES-1:0] free_mask;
    reg [VOICES-1:0] rel_mask;
    reg [7:0]        pick;
    reg              picked;
    reg [AGE_W-1:0]  best_age;

    // v_busy 仅表示 gate/按住状态，用作显示；不包含 Release 中仍有声音的声部。
    assign v_busy = v_gate;

    // ------------------------------------------------------- pick a voice --
    always @(*) begin
        free_mask = {VOICES{1'b0}};
        rel_mask  = {VOICES{1'b0}};
        best_age  = {AGE_W{1'b0}}; // assigned on every path so no latch is inferred
        for (k = 0; k < VOICES; k = k + 1) begin
            free_mask[k] = voice_idle[k] & ~v_gate[k];
            rel_mask[k]  = ~v_gate[k];
        end

        pick   = 8'd0;
        picked = 1'b0;

        // 1. A repeated Note On uses its existing held voice.
        for (k = 0; k < VOICES; k = k + 1)
            if (!picked && v_gate[k] && (v_note[k*7 +: 7] == ev_note)) begin
                pick   = k[7:0];
                picked = 1'b1;
            end

        // 2. envelope already at zero
        for (k = 0; k < VOICES; k = k + 1)
            if (!picked && free_mask[k]) begin
                pick   = k[7:0];
                picked = 1'b1;
            end

        // 3. oldest voice in release
        if (!picked) begin
            best_age = {AGE_W{1'b0}};
            for (k = 0; k < VOICES; k = k + 1)
                if (rel_mask[k] && (!picked || (v_age[k*AGE_W +: AGE_W] > best_age))) begin
                    best_age = v_age[k*AGE_W +: AGE_W];
                    pick     = k[7:0];
                    picked   = 1'b1;
                end
        end

        // 4. oldest held voice
        if (!picked) begin
            best_age = {AGE_W{1'b0}};
            for (k = 0; k < VOICES; k = k + 1)
                if (!picked || (v_age[k*AGE_W +: AGE_W] > best_age)) begin
                    best_age = v_age[k*AGE_W +: AGE_W];
                    pick     = k[7:0];
                    picked   = 1'b1;
                end
        end
    end

    // ------------------------------------------------------ update voices --
    always @(posedge clk) begin
        if (rst) begin
            v_gate  <= {VOICES{1'b0}};
            v_note  <= {(VOICES*7){1'b0}};
            v_vel   <= {(VOICES*8){1'b0}};
            v_start <= {VOICES{1'b0}};
            for (j = 0; j < VOICES; j = j + 1)
                v_age[j*AGE_W +: AGE_W] <= j[AGE_W-1:0];
        end else begin
            // v_start 每 clk 默认清零，供 poly_voice 暂存到下个采样点。
            v_start <= {VOICES{1'b0}};
            if (panic) begin
                v_gate <= {VOICES{1'b0}};
            end else if (ev_valid) begin
                if (ev_on) begin
                    v_gate[pick]         <= 1'b1;
                    v_note[pick*7 +: 7] <= ev_note;
                    v_vel[pick*8 +: 8]  <= ev_vel;
                    v_start[pick]       <= 1'b1;
                    for (j = 0; j < VOICES; j = j + 1) begin
                        if (j == pick)
                            v_age[j*AGE_W +: AGE_W] <= {AGE_W{1'b0}};
                        else if (v_age[j*AGE_W +: AGE_W] < v_age[pick*AGE_W +: AGE_W])
                            v_age[j*AGE_W +: AGE_W] <= v_age[j*AGE_W +: AGE_W] + 1'b1;
                    end
                end else begin
                    for (k = 0; k < VOICES; k = k + 1)
                        if (v_gate[k] && (v_note[k*7 +: 7] == ev_note))
                            v_gate[k] <= 1'b0;
                end
            end
        end
    end

endmodule
