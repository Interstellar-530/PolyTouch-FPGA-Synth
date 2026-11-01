// 7 位 MIDI 音高 -> 32 位 DDS 相位增量，组合逻辑，无额外寄存延迟。
// 当前 PT8211 调试路径 Fs=46875 Hz（27 MHz / 18 / 32），
// phase_inc = round(f * 2^32 / Fs)。未来标准 I2S 的 48 kHz 必须重生成这些常数。
// 仅存 MIDI 0 起始的十二个半音常数，按八度左移即倍频；基础常数舍入误差
// 也随左移放大。只有 12 项频率常数，因此 case 合理，不能类推为大型波表。
// 现有常数由 tools/gen_song_rom.py 生成；改采样率时同时核对生成器设置。
// 本模块不检查可播放音域/奈奎斯特界限；更换波形后需由上层限制高音或带限。
module note_phase_inc (
    input  wire [6:0]  note,
    output reg  [31:0] inc
);

    reg  [31:0] base;
    wire [6:0]  semi     = note % 7'd12;
    wire [6:0]  oct_full = note / 7'd12;
    wire [3:0]  oct      = oct_full[3:0];

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
        inc = base << oct;
    end

endmodule
