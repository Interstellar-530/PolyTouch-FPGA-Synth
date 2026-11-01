// Stereo frame bridge: the audio reference domain owns the 48 kHz frame edge;
// the compute domain returns one atomic {frame_id, left, right} bundle and keeps
// it stable until the reference side acknowledges the capture.
module audio_frame_bridge_stereo(
 input  wire        clk_audio,reset_audio,tick_audio,
 input  wire        clk_compute,reset_compute,
 output wire        tick_compute,
 input  wire signed[23:0] left_compute,right_compute,
 input  wire        valid_compute,
 output reg  signed[23:0] left_audio,right_audio,
 output reg         valid_audio,
 output reg  [7:0]  frame_id_audio
);
 reg req_toggle=0;
 (* ASYNC_REG="TRUE" *) reg req_meta=0,req_sync=0;
 reg req_seen=0;
 reg signed[23:0] left_hold=0,right_hold=0;
 reg [7:0] frame_hold=0,frame_count=0;
 reg res_toggle=0,pending=0;
 reg ack_toggle=0;
 (* ASYNC_REG="TRUE" *) reg ack_meta=0,ack_sync=0;
 reg ack_seen=0;
 (* ASYNC_REG="TRUE" *) reg res_meta=0,res_sync=0;
 reg res_seen=0;

 // request: audio tick -> compute pulse
 always @(posedge clk_audio or posedge reset_audio)begin
  if(reset_audio)req_toggle<=0;
  else if(tick_audio)req_toggle<=!req_toggle;
 end
 always @(posedge clk_compute or posedge reset_compute)begin
  if(reset_compute)begin req_meta<=0;req_sync<=0;req_seen<=0;end
  else begin req_meta<=req_toggle;req_sync<=req_meta;req_seen<=req_sync;end
 end
 assign tick_compute=req_sync^req_seen;

 // result: compute holds the bundle until the audio side acknowledges
 always @(posedge clk_compute or posedge reset_compute)begin
  if(reset_compute)begin
   left_hold<=0;right_hold<=0;frame_hold<=0;frame_count<=0;res_toggle<=0;pending<=0;
   ack_meta<=0;ack_sync<=0;ack_seen<=0;
  end else begin
   ack_meta<=ack_toggle;ack_sync<=ack_meta;ack_seen<=ack_sync;
   if(ack_sync^ack_seen)pending<=0;
   if(valid_compute && !pending)begin
    left_hold<=left_compute;right_hold<=right_compute;
    frame_hold<=frame_count;frame_count<=frame_count+1'b1;
    res_toggle<=!res_toggle;pending<=1;
   end
  end
 end

 // audio side: capture the held bundle when the result tag crosses
 always @(posedge clk_audio or posedge reset_audio)begin
  if(reset_audio)begin
   res_meta<=0;res_sync<=0;res_seen<=0;ack_toggle<=0;
   left_audio<=0;right_audio<=0;valid_audio<=0;frame_id_audio<=0;
  end else begin
   res_meta<=res_toggle;res_sync<=res_meta;res_seen<=res_sync;
   valid_audio<=0;
   if(res_sync^res_seen)begin
    left_audio<=left_hold;right_audio<=right_hold;
    frame_id_audio<=frame_hold;valid_audio<=1;ack_toggle<=!ack_toggle;
   end
  end
 end

`ifdef SIMULATION
 reg request_outstanding=0;
 always @(posedge clk_compute or posedge reset_compute)begin
  if(reset_compute)request_outstanding<=0;
  else begin
   if(tick_compute && request_outstanding)
    $fatal(1,"stereo frame bridge missed the previous compute deadline");
   if(valid_compute && !request_outstanding)
    $fatal(1,"stereo frame bridge received a result without a request");
   if(valid_compute && pending)
    $fatal(1,"stereo frame bridge result arrived before prior acknowledgement");
   case({tick_compute,valid_compute})
    2'b10:request_outstanding<=1;
    2'b01:request_outstanding<=0;
    default:request_outstanding<=request_outstanding;
   endcase
  end
 end
`endif
endmodule
