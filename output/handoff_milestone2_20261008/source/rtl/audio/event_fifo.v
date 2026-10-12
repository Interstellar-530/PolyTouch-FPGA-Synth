// Small synchronous FIFO for note events.
//
// The event word is {on, note[6:0], velocity[7:0]}.  The sequencer writes
// into it and the voice allocator drains it one event per clock, which keeps a
// burst of voice changes from colliding on a single sample tick.  Sixteen
// entries of sixteen bits fit in distributed logic and do not consume BSRAM.
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

    localparam integer AW = 4;      // log2(DEPTH) for DEPTH = 16

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [AW:0]      wr_ptr;
    reg [AW:0]      rd_ptr;

    assign empty   = (wr_ptr == rd_ptr);
    assign full    = (wr_ptr[AW] != rd_ptr[AW]) && (wr_ptr[AW-1:0] == rd_ptr[AW-1:0]);
    // A simultaneous read frees a slot even when the FIFO starts full.
    assign wr_ready = !full || (rd_en && !empty);
    assign rd_data = mem[rd_ptr[AW-1:0]];

    always @(posedge clk) begin
        if (rst) begin
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
