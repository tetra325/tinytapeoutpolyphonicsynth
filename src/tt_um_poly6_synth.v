// tt_um_poly6_synth.v
// Tiny Tapeout wrapper for 6-voice multiplier-free subtractive synthesizer.
// Target clock: 12 MHz -> 46.875 kHz sample_tick via i2s_tx.
module tt_um_poly6_synth (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // Always 1 when the design is powered
    input  wire       clk,      // Clock (12 MHz)
    input  wire       rst_n     // Active-low reset
);
    wire _unused_ena = ena;

    // All uio pins configured as inputs for MIDI RX + envelope shift controls
    assign uio_oe  = 8'h00;
    assign uio_out = 8'h00;

    wire [1:0] wave_sel     = ui_in[1:0];
    wire [2:0] cutoff_shift = ui_in[4:2];
    wire [2:0] res_shift    = ui_in[7:5];

    wire       midi_rx_in   = uio_in[0];
    wire [2:0] atk_shift    = uio_in[3:1];
    wire [2:0] dec_shift    = uio_in[6:4];
    wire       _unused_uio7 = uio_in[7];

    // Compact defaults for sustain & release to keep pin count & logic lean
    localparam [2:0] SUSTAIN_3B = 3'd6;
    localparam [2:0] REL_SHIFT  = 3'd3;

    wire i2s_sdata;
    wire i2s_bclk;
    wire i2s_lrck;
    wire any_gate;

    synth_top #(
        .CLK_HZ(12_000_000),
        .BAUD(31250),
        .VOICES(6),
        .PHASE_W(20),
        .DATA_W(12),
        .ACC_W(16)
    ) u_synth (
        .clk          (clk),
        .rst_n        (rst_n),
        .midi_rx_in   (midi_rx_in),
        .wave_sel     (wave_sel),
        .cutoff_shift (cutoff_shift),
        .res_shift    (res_shift),
        .atk_shift    (atk_shift),
        .dec_shift    (dec_shift),
        .sustain_3b   (SUSTAIN_3B),
        .rel_shift    (REL_SHIFT),
        .gate         (any_gate),
        .bclk         (i2s_bclk),
        .lrck         (i2s_lrck),
        .sdata        (i2s_sdata)
    );

    assign uo_out[0]   = i2s_sdata;
    assign uo_out[1]   = i2s_bclk;
    assign uo_out[2]   = i2s_lrck;
    assign uo_out[3]   = any_gate;
    assign uo_out[7:4] = 4'b0000;

endmodule
