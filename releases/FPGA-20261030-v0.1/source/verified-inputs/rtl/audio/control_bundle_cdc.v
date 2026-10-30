// Coherent held-bus request/ack transfer. Source data stays fixed until ack.
module control_bundle_cdc #(parameter integer WIDTH=16)(
    input wire src_clk,src_reset,src_valid,
    input wire [WIDTH-1:0] src_data,
    output wire src_ready,
    input wire dst_clk,dst_reset,
    output reg dst_valid,
    output reg [WIDTH-1:0] dst_data,
    input wire dst_ready
);
    reg [WIDTH-1:0] held=0;
    reg req=0,ack=0,seen=0;
    (* ASYNC_REG="TRUE" *) reg ack_meta=0,ack_sync=0,req_meta=0,req_sync=0;
    assign src_ready=(ack_sync==req) && !src_reset;
    always @(posedge src_clk or posedge src_reset) begin
        if(src_reset) begin held<=0;req<=0;ack_meta<=0;ack_sync<=0;end
        else begin
            ack_meta<=ack;ack_sync<=ack_meta;
            if(src_valid && src_ready) begin held<=src_data;req<=~req;end
        end
    end
    always @(posedge dst_clk or posedge dst_reset) begin
        if(dst_reset) begin req_meta<=0;req_sync<=0;seen<=0;ack<=0;dst_valid<=0;dst_data<=0;end
        else begin
            req_meta<=req;req_sync<=req_meta;
            if(req_sync!=seen && !dst_valid) begin
                dst_data<=held;dst_valid<=1;seen<=req_sync;
            end
            if(dst_valid && dst_ready) begin dst_valid<=0;ack<=seen;end
        end
    end
endmodule
