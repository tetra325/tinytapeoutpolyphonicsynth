// i2s_tx.v
// Standard I2S serial transmitter (16-bit per channel, 64 BCLKs/frame).
// Divides clk by 256 per audio frame (BCLK = clk/4, LRCK = clk/256).
module i2s_tx #(
    parameter AUDIO_W = 12
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire signed [AUDIO_W-1:0]   audio_in,
    output wire                        sample_tick, // Pulses 1 clk once every 256 clks
    output wire                        bclk,
    output wire                        lrck,
    output wire                        sdata
);

    reg [7:0]  cnt;
    reg [15:0] shift_reg;

    // bclk = cnt[1] falls when cnt[1:0] == 2'b00
    wire bclk_fall = (cnt[1:0] == 2'b00);
    wire [4:0] bit_idx = cnt[6:2]; // 0..31 within each half-frame

    // Left-align signed AUDIO_W into 16-bit word (pad lower bits with 0)
    wire signed [15:0] audio_16_s = {{(16-AUDIO_W){audio_in[AUDIO_W-1]}}, audio_in} <<< (16 - AUDIO_W);
    wire [15:0] audio_16 = audio_16_s;

    assign sample_tick = (cnt == 8'd255);
    assign bclk        = cnt[1];
    assign lrck        = cnt[7]; // 0 = Left, 1 = Right
    // Output 0 during bit_idx == 0 (1-BCLK I2S alignment after LRCK edge)
    assign sdata       = (bit_idx == 5'd0) ? 1'b0 : shift_reg[15];

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt       <= 8'd0;
            shift_reg <= 16'd0;
        end else begin
            cnt <= cnt + 8'd1;

            // Load audio_16 at the end of each half-frame (cnt == 127 or 255)
            // so shift_reg[15] (MSB) is ready right as bit_idx becomes 1
            if (cnt == 8'd127 || cnt == 8'd255) begin
                shift_reg <= audio_16;
            end else if (bclk_fall && (bit_idx >= 5'd2) && (bit_idx <= 5'd16)) begin
                shift_reg <= {shift_reg[14:0], 1'b0};
            end
        end
    end

endmodule
