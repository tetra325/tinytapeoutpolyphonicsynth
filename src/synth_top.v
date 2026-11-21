// synth_top.v
// 6-voice multiplier-free subtractive synthesizer top-level.
// Clock: 12 MHz -> sample_tick every 256 clks (46.875 kHz) via i2s_tx.
module synth_top #(
    parameter integer CLK_HZ  = 12_000_000,
    parameter integer BAUD    = 31250,
    parameter integer VOICES  = 6,
    parameter         PHASE_W = 20,
    parameter         DATA_W  = 12,
    parameter         ACC_W   = 16
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              midi_rx_in,
    input  wire [1:0]        wave_sel,
    input  wire [2:0]        cutoff_shift,
    input  wire [2:0]        res_shift,
    input  wire [2:0]        atk_shift,
    input  wire [2:0]        dec_shift,
    input  wire [2:0]        sustain_3b,
    input  wire [2:0]        rel_shift,
    output wire              gate,
    output wire              bclk,
    output wire              lrck,
    output wire              sdata
);

    wire [7:0]                     rx_byte;
    wire                           byte_valid;
    wire [VOICES-1:0]              voice_gate;
    wire [VOICES*PHASE_W-1:0]      phase_inc_bus;
    wire [VOICES*16-1:0]           env_bus;
    wire signed [VOICES*DATA_W-1:0] voice_out_bus;

    wire                           sample_tick;
    wire signed [DATA_W-1:0]       mix_out;
    wire signed [DATA_W-1:0]       vcf_out;

    midi_rx #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD)
    ) u_midi_rx (
        .clk(clk),
        .rst_n(rst_n),
        .midi_rx_in(midi_rx_in),
        .rx_byte(rx_byte),
        .byte_valid(byte_valid)
    );

    poly_note_ctrl #(
        .VOICES(VOICES),
        .PHASE_W(PHASE_W)
    ) u_poly_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .rx_byte(rx_byte),
        .byte_valid(byte_valid),
        .env_bus(env_bus),
        .voice_gate(voice_gate),
        .phase_inc_bus(phase_inc_bus),
        .any_gate(gate)
    );

    genvar g;
    generate
        for (g = 0; g < VOICES; g = g + 1) begin : gen_voices
            wire signed [DATA_W-1:0] v_wave;
            wire signed [DATA_W-1:0] v_env_audio;
            wire [15:0]              v_env;

            vco #(
                .PHASE_W(PHASE_W),
                .OUT_W(DATA_W)
            ) u_vco (
                .clk(clk),
                .rst_n(rst_n),
                .sample_tick(sample_tick),
                .wave_sel(wave_sel),
                .phase_inc(phase_inc_bus[g*PHASE_W +: PHASE_W]),
                .wave_out(v_wave)
            );

            adsr_vca #(
                .AUDIO_W(DATA_W),
                .RATE_DIV(64)
            ) u_adsr_vca (
                .clk(clk),
                .rst_n(rst_n),
                .sample_tick(sample_tick),
                .gate(voice_gate[g]),
                .atk_shift(atk_shift),
                .dec_shift(dec_shift),
                .sustain_3b(sustain_3b),
                .rel_shift(rel_shift),
                .audio_in(v_wave),
                .audio_out(v_env_audio),
                .env_out(v_env)
            );

            assign env_bus[g*16 +: 16]             = v_env;
            assign voice_out_bus[g*DATA_W +: DATA_W] = v_env_audio;
        end
    endgenerate

    // Multiplier-free 6-voice sum + right-shift by 3 (/8 headroom)
    wire signed [DATA_W-1:0] v0 = voice_out_bus[0*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] v1 = voice_out_bus[1*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] v2 = voice_out_bus[2*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] v3 = voice_out_bus[3*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] v4 = voice_out_bus[4*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] v5 = voice_out_bus[5*DATA_W +: DATA_W];

    wire signed [DATA_W+3:0] poly_sum =
        {{4{v0[DATA_W-1]}}, v0} + {{4{v1[DATA_W-1]}}, v1} + {{4{v2[DATA_W-1]}}, v2} +
        {{4{v3[DATA_W-1]}}, v3} + {{4{v4[DATA_W-1]}}, v4} + {{4{v5[DATA_W-1]}}, v5};

    wire signed [DATA_W-1:0] poly_scaled = poly_sum[DATA_W+3:3];
    assign mix_out = poly_scaled;

    vcf_svf #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) u_vcf (
        .clk(clk),
        .rst_n(rst_n),
        .sample_tick(sample_tick),
        .cutoff_shift(cutoff_shift),
        .res_shift(res_shift),
        .audio_in(mix_out),
        .lpf_out(vcf_out)
    );

    i2s_tx #(
        .AUDIO_W(DATA_W)
    ) u_i2s (
        .clk(clk),
        .rst_n(rst_n),
        .audio_in(vcf_out),
        .sample_tick(sample_tick),
        .bclk(bclk),
        .lrck(lrck),
        .sdata(sdata)
    );

endmodule
