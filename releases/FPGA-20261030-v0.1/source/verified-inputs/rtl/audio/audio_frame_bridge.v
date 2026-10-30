// One frame request and one held sample per48kHz frame. Toggle controls cross
// through two registers; the sample bus is stable before its synchronized tag.
module audio_frame_bridge(
 input wire clk_audio,reset_audio,tick_audio,
 input wire clk_compute,reset_compute,
 output wire tick_compute,
 input wire signed[23:0]sample_compute,input wire valid_compute,
 output reg signed[23:0]sample_audio=0,output reg valid_audio=0
);
 reg request_toggle=0;
 (* ASYNC_REG="TRUE" *)reg request_meta=0,request_sync=0;
 reg request_seen=0;
 reg signed[23:0]sample_hold=0;
 reg result_toggle=0;
 (* ASYNC_REG="TRUE" *)reg result_meta=0,result_sync=0;
 reg result_seen=0;
 always @(posedge clk_audio or posedge reset_audio)begin
  if(reset_audio)request_toggle<=0;
  else if(tick_audio)request_toggle<=!request_toggle;
 end
 always @(posedge clk_compute or posedge reset_compute)begin
  if(reset_compute)begin request_meta<=0;request_sync<=0;request_seen<=0;end
  else begin request_meta<=request_toggle;request_sync<=request_meta;request_seen<=request_sync;end
 end
 assign tick_compute=request_sync ^ request_seen;
 always @(posedge clk_compute or posedge reset_compute)begin
  if(reset_compute)begin sample_hold<=0;result_toggle<=0;end
  else if(valid_compute)begin sample_hold<=sample_compute;result_toggle<=!result_toggle;end
 end
 always @(posedge clk_audio or posedge reset_audio)begin
  if(reset_audio)begin result_meta<=0;result_sync<=0;result_seen<=0;sample_audio<=0;valid_audio<=0;end
  else begin
   result_meta<=result_toggle;result_sync<=result_meta;result_seen<=result_sync;valid_audio<=0;
   if(result_sync!=result_seen)begin sample_audio<=sample_hold;valid_audio<=1;end
  end
 end
endmodule
