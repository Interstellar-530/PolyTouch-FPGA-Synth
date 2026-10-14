`timescale 1ns/1ps
// [S2-AI 新增] 本测试台由 AI 于 2026-10-14 为缺件期间任务清单 S2 编写，供后续智能体复查。
// 覆盖：空闲无事件、短抖动不触发、一次按/松各一个事件、按住不重触发、
// 12 键同拍、下游停顿时的背压与“先松键后按键”顺序、flush 后须松开再按、
// 以及按下到事件的数字响应上界。
module tb_gpio_keyboard;

    localparam integer KEYS    = 12;
    localparam integer PRESS   = 27000;   // 必须与 gpio_keyboard 默认门限保持一致
    localparam integer RELEASE = 81000;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg flush = 1'b0;
    reg ev_ready = 1'b1;
    reg [KEYS-1:0] key_in = {KEYS{1'b1}};

    wire ev_valid, ev_on;
    wire [6:0] ev_note;
    wire [7:0] ev_vel;

    integer events, ons, offs, i, latency;
    reg [KEYS-1:0] seen_on, seen_off;
    reg [7:0] seq_on   [0:63];
    integer   seq_note [0:63];
    integer   seq_len;

    always #18.5185 clk = ~clk;

    gpio_keyboard dut (
        .clk(clk), .rst(rst), .key_in(key_in), .flush(flush), .ev_ready(ev_ready),
        .ev_valid(ev_valid), .ev_on(ev_on), .ev_note(ev_note), .ev_vel(ev_vel),
        .key_pressed()
    );

    // 事件观察器：只统计真正被下游接受的事件（ev_valid 且 ev_ready）。
    always @(posedge clk) begin
        if (ev_valid && ev_ready) begin
            events = events + 1;
            if (ev_on) begin
                ons = ons + 1;
                seen_on[ev_note - 7'd60] = 1'b1;
            end else begin
                offs = offs + 1;
                seen_off[ev_note - 7'd60] = 1'b1;
            end
            if (seq_len < 64) begin
                seq_on[seq_len]   = ev_on;
                seq_note[seq_len] = ev_note;
                seq_len = seq_len + 1;
            end
        end
    end

    task wait_cycles;
        input integer n;
        integer c;
        begin
            for (c = 0; c < n; c = c + 1) @(negedge clk);
        end
    endtask

    task clear_stats;
        begin
            events = 0;
            ons = 0;
            offs = 0;
            seq_len = 0;
            seen_on = {KEYS{1'b0}};
            seen_off = {KEYS{1'b0}};
        end
    endtask

    task check;
        input [255:0] what;
        input integer got;
        input integer want;
        begin
            if (got !== want) begin
                $display("FAIL %0s: got %0d want %0d", what, got, want);
                $fatal(1, "tb_gpio_keyboard failed");
            end else begin
                $display("ok   %0s = %0d", what, got);
            end
        end
    endtask

    initial begin
        rst = 1'b1;
        wait_cycles(20);
        rst = 1'b0;
        wait_cycles(20);

        // 阶段 1：全部松开时不得产生任何事件。
        clear_stats;
        wait_cycles(200000);
        check("idle emits no event", events, 0);

        // 阶段 2：连续短抖动都比按下门限短，不得触发。
        clear_stats;
        for (i = 0; i < 8; i = i + 1) begin
            key_in[0] = 1'b0;
            wait_cycles(PRESS - 2000);
            key_in[0] = 1'b1;
            wait_cycles(2000);
        end
        wait_cycles(RELEASE);
        check("short jitter never commits", events, 0);

        // 阶段 3：一次按下只有一个事件，按住期间不重触发。
        clear_stats;
        key_in[0] = 1'b0;
        wait_cycles(PRESS + 20);
        check("one press yields one event", events, 1);
        check("first event is Note On", ons, 1);
        check("key 0 maps to C4 (60)", seq_note[0], 60);
        wait_cycles(200000);
        check("held key does not retrigger", events, 1);

        key_in[0] = 1'b1;
        wait_cycles(RELEASE + 20);
        check("one release yields one event", events, 2);
        check("second event is Note Off", offs, 1);
        wait_cycles(200000);
        check("held release does not repeat", events, 2);

        // 阶段 4：12 键同拍按下与同样同拍松开，事件一个都不能少。
        clear_stats;
        key_in = {KEYS{1'b0}};
        wait_cycles(PRESS + 30);
        check("12-key press event count", events, 12);
        check("12-key press all Note On", ons, 12);
        for (i = 0; i < KEYS; i = i + 1)
            if (!seen_on[i]) $fatal(1, "12-key press missed key %0d", i);

        key_in = {KEYS{1'b1}};
        wait_cycles(RELEASE + 30);
        check("12-key release all Note Off", offs, 12);
        for (i = 0; i < KEYS; i = i + 1)
            if (!seen_off[i]) $fatal(1, "12-key release missed key %0d", i);

        // 阶段 5：下游停顿时的背压。键 0..3 先按住，随后一组松开、一组按下，
        // 两个门限不同但可以在同一拍提交；此时队列里应同时有 4 个 Off 和 4 个 On，
        // 放行后必须“先全部 Off，再全部 On”，一个都不丢。
        clear_stats;
        key_in = {KEYS{1'b1}};
        key_in[3:0] = 4'b0000;
        wait_cycles(PRESS + 20);
        check("preload keys 0..3", events, 4);

        ev_ready = 1'b0;              // 下游停顿：事件只能留在队列里
        clear_stats;
        key_in[3:0] = 4'b1111;        // 松开键 0..3
        wait_cycles(RELEASE - PRESS); // 再等 54000 拍后按下键 4..7，使两组同拍提交
        key_in[7:4] = 4'b0000;
        wait_cycles(PRESS + 20);
        check("backpressure holds all events", events, 0);

        ev_ready = 1'b1;
        wait_cycles(KEYS + 30);
        check("backpressure burst total", events, 8);
        check("backpressure burst Off count", offs, 4);
        check("backpressure burst On count", ons, 4);
        for (i = 0; i < 4; i = i + 1) begin
            if (seq_on[i] !== 1'b0)
                $fatal(1, "burst order: event %0d should be Note Off", i);
            if (seq_note[i] !== (60 + i))
                $fatal(1, "burst order: event %0d note=%0d want %0d", i, seq_note[i], 60 + i);
        end
        for (i = 4; i < 8; i = i + 1) begin
            if (seq_on[i] !== 1'b1)
                $fatal(1, "burst order: event %0d should be Note On", i);
            if (seq_note[i] !== (60 + i))
                $fatal(1, "burst order: event %0d note=%0d want %0d", i, seq_note[i], 60 + i);
        end
        key_in = {KEYS{1'b1}};
        wait_cycles(RELEASE + 30);

        // 阶段 6：flush（对应顶层 Panic 与模式切换）后必须松开再按才会重新起音。
        clear_stats;
        key_in = {KEYS{1'b1}};
        key_in[0] = 1'b0;
        wait_cycles(PRESS + 20);
        check("setup before flush", events, 1);

        flush = 1'b1;
        @(negedge clk);
        flush = 1'b0;
        wait_cycles(200000);
        check("flush keeps held key silent", events, 1);

        key_in[0] = 1'b1;
        wait_cycles(RELEASE + 20);
        // flush 已经撤销了该键的按键记录，松开时仍会补一个 Note Off；
        // 顶层声部分配器对没有对应 gate 的 Note Off 不动作，因此无害。
        check("release after flush emits one Off", offs, 1);

        clear_stats;
        key_in[0] = 1'b0;
        wait_cycles(PRESS + 20);
        check("re-press after flush sounds again", ons, 1);
        key_in[0] = 1'b1;
        wait_cycles(RELEASE + 20);
        check("re-press release emits one Off", offs, 1);

        // 阶段 7：数字响应上界。从引脚拉低到事件被接受不得超过
        // 按下消抖拍数加少许队列/同步开销。
        clear_stats;
        key_in = {KEYS{1'b1}};
        wait_cycles(50);
        latency = 0;
        key_in[0] = 1'b0;
        while (!(ev_valid && ev_ready)) begin
            @(negedge clk);
            latency = latency + 1;
            if (latency > PRESS + 60)
                $fatal(1, "press-to-event latency exceeded bound");
        end
        $display("ok   press-to-event latency = %0d cycles (bound %0d)", latency, PRESS + 60);
        key_in[0] = 1'b1;
        wait_cycles(RELEASE + 20);

        $display("PASS tb_gpio_keyboard: sync, debounce, edge, burst, backpressure, flush, bound");
        $finish;
    end

    initial begin
        #400000000;
        $fatal(1, "FAIL tb_gpio_keyboard: timeout");
    end
endmodule
