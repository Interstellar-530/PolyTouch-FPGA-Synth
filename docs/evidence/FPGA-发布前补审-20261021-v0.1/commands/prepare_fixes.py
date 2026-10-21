"""Preserve incoming integration, isolate its RAM variant and retain reviewed fixes."""
from pathlib import Path
import hashlib,json,shutil
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'.git').exists())
OUT=Path(__file__).resolve().parents[1];SRC=ROOT/'output/handoff_milestone2_20261008/source'
BASE=ROOT/'archive/FPGA-20261021-v0.8/source'
names=['rtl/prototypes/voice_sched32.v','rtl/prototypes/ram32_top.v','rtl/prototypes/instrument_rom_banks.v',
       'rtl/audio/ram_wavetable_engine.v','rtl/audio/ram_audio_compute.v','rtl/audio/ram_audio_datapath.v',
       'build/ram32_proto.tcl','sim/tb_ram32_complete.v','sim/tb_voice_sched32_review.v','sim/run_simulation.ps1']
for name in names:
    dst=OUT/'before'/name;dst.parent.mkdir(parents=True,exist_ok=True)
    assert not dst.exists(),'Do not overwrite incoming snapshots'
    shutil.copy2(SRC/name,dst)
mapping={x:'instrument_'+x for x in ['ram_wavetable_engine','ram_audio_compute','ram_audio_datapath']}
for old,new in mapping.items():
    data=(SRC/f'rtl/audio/{old}.v').read_text()
    for a,b in mapping.items():data=data.replace(a,b)
    (SRC/f'rtl/prototypes/{new}.v').write_text(data,encoding='utf-8')
    shutil.copy2(BASE/f'rtl/audio/{old}.v',SRC/f'rtl/audio/{old}.v')
top=SRC/'rtl/prototypes/ram32_top.v'
top.write_text(top.read_text().replace('ram_audio_datapath #','instrument_ram_audio_datapath #'),encoding='utf-8')
tcl=SRC/'build/ram32_proto.tcl';data=tcl.read_text()
for a,b in mapping.items():data=data.replace(f'rtl/audio/{a}.v',f'rtl/prototypes/{b}.v')
data=data.replace('[file join $root .. .. tmp ram32_proto_run]','[file join $root .. .. .. tmp ram32_proto_run]')
tcl.write_text(data,encoding='utf-8')

# Start with the last reviewed scheduler, retaining its queue, rank and handshake fixes.
data=(BASE/'rtl/prototypes/voice_sched32.v').read_text()
data=data.replace('parameter integer FS_HZ = 48000','parameter integer FS_HZ = 48000,\n    parameter integer STAGE_STEP_SAMPLES = 5859')
data=data.replace('input  wire        ev_valid,','input  wire        instrument,\n    input  wire [1:0]  piano_tone,\n    input  wire        ev_valid,')
data=data.replace('output wire        cfg_valid,','output wire [23:0] cfg_param,\n    output wire        cfg_valid,')
data=data.replace('reg [VOICES-1:0] dirty;', '''reg [VOICES-1:0] dirty;
    reg [2:0] stage_q[0:VOICES-1];
    reg [12:0] timer[0:VOICES-1];
    reg instrument_q;
    reg [1:0] tone_q;
    wire [2:0] start_stage=(tone_q>=3)?3'd4:3'd3;''')
data=data.replace('reg [6:0]  sel_note;','reg [31:0] cfg_inc_q;\n    reg [23:0] cfg_param_q;')
data=data.replace('wire [31:0] sel_inc;\n    note_phase_inc #(.FS_HZ(FS_HZ)) u_inc (.note(sel_note), .inc(sel_inc));','')
anchor='    always @(posedge clk) begin\n        if (rst) begin'
comb='''    wire [31:0] candidate_inc;
    note_phase_inc #(.FS_HZ(FS_HZ)) u_inc(.note(note[dirty_sel]),.inc(candidate_inc));
    // Use note boundaries, preserving the production 46.875kHz musical mapping
    // when the prototype runs at 48kHz. Piano group 1 starts at MIDI 78.
    wire [2:0] candidate_band=note[dirty_sel]<48?0:note[dirty_sel]<60?1:
        note[dirty_sel]<67?2:note[dirty_sel]<76?3:note[dirty_sel]<84?4:5;
    wire [2:0] candidate_group=candidate_band<=1?0:candidate_band-1'b1;
    wire [2:0] candidate_variant=candidate_band<=1?
        (vel[dirty_sel]>=112?5:2):vel[dirty_sel]>=112?5:vel[dirty_sel]>=96?4:
        vel[dirty_sel]>=64?2:vel[dirty_sel]>=32?1:0;
    wire [2:0] candidate_stage=stage_q[dirty_sel]<start_stage?start_stage-stage_q[dirty_sel]:0;
    wire [5:0] candidate_bank=instrument_q?
        6'd12+candidate_group*6'd6+candidate_variant:
        (note[dirty_sel]>=78?6'd6:6'd0)+candidate_stage;
    wire [15:0] candidate_weight=instrument_q?16'd0:
        ((16'd8191-{3'd0,timer[dirty_sel]})<<3);
'''
assert anchor in data;data=data.replace(anchor,comb+'\n'+anchor)
data=data.replace('retrig[i] <= 1\'b0;','retrig[i] <= 1\'b0; stage_q[i]<=0; timer[i]<=0;')
data=data.replace("sel <= 6'd0; sel_note <= 7'd0;","sel <= 6'd0; cfg_inc_q<=0;cfg_param_q<=0;instrument_q<=0;tone_q<=0;")
data=data.replace('// Event capture: one entry.','''// Latch global timbre at frame boundary and refresh every voice.
            if(sample_tick && ((instrument_q!=instrument)||(tone_q!=piano_tone)))begin
                instrument_q<=instrument;tone_q<=piano_tone;dirty<={VOICES{1'b1}};
            end
            // Event capture: one entry.''')
data=data.replace('if (env_ptr == VOICES - 1) env_run <= 1\'b0;', '''if(!instrument_q && est[env_ptr]!=ST_IDLE)begin
                    if(stage_q[env_ptr]>=start_stage)begin
                        if(timer[env_ptr]!=STAGE_STEP_SAMPLES-1)dirty[env_ptr]<=1;
                        timer[env_ptr]<=STAGE_STEP_SAMPLES-1;
                    end else if(timer[env_ptr]>=STAGE_STEP_SAMPLES-1)begin
                        timer[env_ptr]<=0;stage_q[env_ptr]<=stage_q[env_ptr]+1'b1;dirty[env_ptr]<=1;
                    end else begin timer[env_ptr]<=timer[env_ptr]+1'b1;dirty[env_ptr]<=1;end
                end
                if (env_ptr == VOICES - 1) env_run <= 1'b0;''')
data=data.replace("dirty[pick]  <= 1'b1;","dirty[pick]  <= 1'b1; stage_q[pick]<=0;timer[pick]<=0;")
start=data.index('            if (cfg_pend) begin')
end=data.index('\n        end\n    end',start)
data=data[:start]+'''            // Prefetch the next stable snapshot while the core accepts the
            // previous one, sustaining one three-word transaction per 4 clocks.
            if(!cfg_pend || cfg_ready)begin
                if(dirty_any && !env_run && !sample_tick && ev_state!=EV_COMMIT)begin
                    sel<=dirty_sel;cfg_inc_q<=candidate_inc;
                    cfg_env_q<=env[dirty_sel];cfg_vel_q<=vel[dirty_sel][6:0];
                    cfg_retrig_q<=retrig[dirty_sel];cfg_param_q<={2'd0,candidate_bank,candidate_weight};
                    cfg_pend<=1;dirty[dirty_sel]<=0;retrig[dirty_sel]<=0;
                end else cfg_pend<=0;
            end'''+data[end:]
data=data.replace('assign cfg_increment = sel_inc;','assign cfg_increment = cfg_inc_q;\n    assign cfg_param = cfg_param_q;')
data=data.replace('initial if (VOICES < 1 || VOICES > 32)','initial if (STAGE_STEP_SAMPLES<1 || STAGE_STEP_SAMPLES>8192 || VOICES < 1 || VOICES > 32)')
(SRC/'rtl/prototypes/voice_sched32.v').write_text(data,encoding='utf-8')
result={name:hashlib.sha256((SRC/name).read_bytes()).hexdigest() for name in names}
(OUT/'prepared_inputs.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print('Incoming integration saved; legacy RAM interface restored; reviewed scheduler fixes retained.')
