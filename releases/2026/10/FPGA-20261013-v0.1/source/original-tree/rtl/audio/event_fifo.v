// 演示音符事件 FIFO，默认 16 项，事件为 {on, note[6:0], velocity[7:0]}。
// 写入/读指针在 clk 上升沿更新，rd_data 是当前读指针的组合输出。
// 只有 wr_en && wr_ready 才表示本拍接受写入；读出条件为 rd_en && !empty。
// top 中仅 song_player 写入此队列，UART 事件另行仲裁，不经过这里。
// 默认容量很小；资源以综合报告为准，本模块不实例化 BSRAM 原语。
module event_fifo #(
    parameter integer DEPTH = 16,
    parameter integer WIDTH = 16
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             wr_en,
    input  wire [WIDTH-1:0] wr_data,
    input  wire             rd_en,
    output wire [WIDTH-1:0] rd_data,
    output wire             empty,
    output wire             full,
    output wire             wr_ready
);

    localparam integer AW = 4;      // 本版固定地址宽度；DEPTH 参数只能按 16 项使用

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [AW:0]      wr_ptr;
    reg [AW:0]      rd_ptr;

    assign empty   = (wr_ptr == rd_ptr);
    assign full    = (wr_ptr[AW] != rd_ptr[AW]) && (wr_ptr[AW-1:0] == rd_ptr[AW-1:0]);
    // 满队列若本拍也读出旧队首，仍可接受新事件；两指针一起前进、占用数不变。
    // 非阻塞写入在采样沿后生效，消费端在该沿取得的仍是原队首。
    assign wr_ready = !full || (rd_en && !empty);
    assign rd_data = mem[rd_ptr[AW-1:0]];

    always @(posedge clk) begin
        if (rst) begin
            // 复位只清指针；旧 mem 内容不再有效，消费者必须遵守 empty。
            wr_ptr <= {AW+1{1'b0}};
            rd_ptr <= {AW+1{1'b0}};
        end else begin
            if (wr_en && wr_ready) begin
                mem[wr_ptr[AW-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (rd_en && !empty)
                rd_ptr <= rd_ptr + 1'b1;
        end
    end

endmodule
