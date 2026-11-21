// vcf_svf.v
// Multiplier-free 2-pole State-Variable Filter (low-pass output) using shifts.
module vcf_svf #(
    parameter DATA_W = 12,
    parameter ACC_W  = 16
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     sample_tick,
    input  wire [2:0]               cutoff_shift, // 1..6 (smaller = higher cutoff)
    input  wire [2:0]               res_shift,    // 2..6 (larger = less damping / more resonance)
    input  wire signed [DATA_W-1:0] audio_in,
    output wire signed [DATA_W-1:0] lpf_out
);

    localparam signed [ACC_W-1:0] ACC_MAX = {1'b0, {(ACC_W-1){1'b1}}};
    localparam signed [ACC_W-1:0] ACC_MIN = {1'b1, {(ACC_W-1){1'b0}}};

    localparam signed [DATA_W-1:0] OUT_MAX = {1'b0, {(DATA_W-1){1'b1}}};
    localparam signed [DATA_W-1:0] OUT_MIN = {1'b1, {(DATA_W-1){1'b0}}};

    localparam integer SHIFT_UP = (ACC_W > DATA_W) ? (ACC_W - DATA_W) : 0;

    reg signed [ACC_W-1:0] low;
    reg signed [ACC_W-1:0] band;

    // Sign-extend and scale input audio into full internal accumulator range
    wire signed [ACC_W-1:0] in_ext =
        {{(ACC_W-DATA_W){audio_in[DATA_W-1]}}, audio_in} <<< SHIFT_UP;

    // High-pass / input error term: in - low - damping*band
    wire signed [ACC_W-1:0] damp_term = band >>> res_shift;
    wire signed [ACC_W+1:0] hp_wide   = {{2{in_ext[ACC_W-1]}}, in_ext} - {{2{low[ACC_W-1]}}, low} - {{2{damp_term[ACC_W-1]}}, damp_term};

    wire signed [ACC_W-1:0] hp_sat =
        (hp_wide > $signed({{2{1'b0}}, ACC_MAX})) ? ACC_MAX :
        (hp_wide < $signed({{2{1'b1}}, ACC_MIN})) ? ACC_MIN :
        hp_wide[ACC_W-1:0];

    wire signed [ACC_W-1:0] f_band_step = hp_sat >>> cutoff_shift;
    wire signed [ACC_W+1:0] band_next_w = {{2{band[ACC_W-1]}}, band} + {{2{f_band_step[ACC_W-1]}}, f_band_step};

    wire signed [ACC_W-1:0] band_next =
        (band_next_w > $signed({{2{1'b0}}, ACC_MAX})) ? ACC_MAX :
        (band_next_w < $signed({{2{1'b1}}, ACC_MIN})) ? ACC_MIN :
        band_next_w[ACC_W-1:0];

    wire signed [ACC_W-1:0] f_low_step  = band_next >>> cutoff_shift;
    wire signed [ACC_W+1:0] low_next_w  = {{2{low[ACC_W-1]}}, low} + {{2{f_low_step[ACC_W-1]}}, f_low_step};

    wire signed [ACC_W-1:0] low_next =
        (low_next_w > $signed({{2{1'b0}}, ACC_MAX})) ? ACC_MAX :
        (low_next_w < $signed({{2{1'b1}}, ACC_MIN})) ? ACC_MIN :
        low_next_w[ACC_W-1:0];

    always @(posedge clk) begin
        if (!rst_n) begin
            low  <= {ACC_W{1'b0}};
            band <= {ACC_W{1'b0}};
        end else if (sample_tick) begin
            band <= band_next;
            low  <= low_next;
        end
    end

    // Scale accumulator output back to DATA_W with saturation
    wire signed [ACC_W-1:0] scaled_low = low >>> SHIFT_UP;

    assign lpf_out = (scaled_low > $signed({{(ACC_W-DATA_W){1'b0}}, OUT_MAX})) ? OUT_MAX :
                     (scaled_low < $signed({{(ACC_W-DATA_W){1'b1}}, OUT_MIN})) ? OUT_MIN :
                     scaled_low[DATA_W-1:0];

endmodule
