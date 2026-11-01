// 7 位 MIDI 音高 -> 32 位 DDS 相位增量，组合逻辑，无额外寄存延迟。
// phase_inc = round(f * 2^32 / Fs)，Fs 由 FS_HZ 选择档案：
//   46875 Hz（PT8211 调试档，27 MHz / 18 / 32）直接使用下表的常数；
//   48000 Hz（标准 I2S 档，12.288 MHz / 256）由同一张表按 46875/48000 = 125/128
//   精确缩放，不维护第二份常数表，避免两张表各自漂移。缩放是整数运算，
//   12 个常数上的附加误差不超过 1 LSB（约 20 ppm，等同 0.03 cent），与表本身的
//   舍入误差同量级；逐值对照见 sim/tb_top_i2s.v 与复核记录。
// 仅存 MIDI 0 起始的十二个半音常数，按八度左移即倍频；基础常数舍入误差
// 也随左移放大。只有 12 项频率常数，因此 case 合理，不能类推为大型波表。
// 现有常数由 tools/gen_song_rom.py 生成；改采样率时同时核对生成器设置。
// 本模块不检查可播放音域/奈奎斯特界限；更换波形后需由上层限制高音或带限。
module note_phase_inc #(
    parameter integer FS_HZ = 46875
) (
    input  wire [6:0]  note,
    output reg  [31:0] inc
);

    reg  [31:0] base;
    wire [6:0]  semi     = note % 7'd12;
    wire [6:0]  oct_full = note / 7'd12;
    wire [3:0]  oct      = oct_full[3:0];

    // base * 125 / 128 = base * (46875 / 48000)。先左移再减三倍，避免除法器；
    // 48 kHz 档的等效值 = round(f * 2^32 / 48000) 的近似，误差见文件头说明。
    wire [31:0] base_48k = (((base << 7) - (base * 3)) >> 7);

    always @(*) begin
        case (semi)
            7'd0:  base = 32'd749115;    // C
            7'd1:  base = 32'd793660;    // C#
            7'd2:  base = 32'd840854;    // D
            7'd3:  base = 32'd890853;    // D#
            7'd4:  base = 32'd943826;    // E
            7'd5:  base = 32'd999949;    // F
            7'd6:  base = 32'd1059409;   // F#
            7'd7:  base = 32'd1122405;   // G
            7'd8:  base = 32'd1189147;   // G#
            7'd9:  base = 32'd1259857;   // A
            7'd10: base = 32'd1334772;   // A#
            default: base = 32'd1414142; // B
        endcase
        inc = ((FS_HZ == 48000) ? base_48k : base) << oct;
    end

endmodule
