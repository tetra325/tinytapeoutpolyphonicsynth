// vco.v
// Multiplier-free VCO with Sawtooth (0), Square (1), and Triangle (2) outputs.
module vco #(
    parameter PHASE_W = 20,
    parameter OUT_W   = 12
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  sample_tick,
    input  wire [1:0]            wave_sel,
    input  wire [PHASE_W-1:0]    phase_inc,
    output reg  signed [OUT_W-1:0] wave_out
);

    reg [PHASE_W-1:0] phase;

    always @(posedge clk) begin
        if (!rst_n) begin
            phase <= {PHASE_W{1'b0}};
        end else if (sample_tick) begin
            phase <= phase + phase_inc;
        end
    end

    // Unsigned top bits for sawtooth
    wire [OUT_W-1:0] saw_u;
    generate
        if (OUT_W <= PHASE_W) begin : gen_saw_narrow
            assign saw_u = phase[PHASE_W-1 -: OUT_W];
        end else begin : gen_saw_wide
            assign saw_u = {phase, {(OUT_W - PHASE_W){1'b0}}};
        end
    endgenerate

    wire signed [OUT_W:0] saw_wide = $signed({1'b0, saw_u}) - $signed({1'b0, 1'b1, {(OUT_W-1){1'b0}}});
    wire signed [OUT_W-1:0] saw_diff = saw_wide[OUT_W-1:0];
    wire signed [OUT_W-1:0] saw_s = saw_diff[OUT_W-1:0];

    // Square: half cycle negative, half cycle positive (3/4 max swing)
    wire signed [OUT_W-1:0] sq_s = phase[PHASE_W-1]
        ?  $signed({1'b0, 1'b1, {(OUT_W-2){1'b0}}})
        : -$signed({1'b0, 1'b1, {(OUT_W-2){1'b0}}});

    // Triangle: rises on first half (phase[PHASE_W-1] == 0), falls on second half (== 1)
    wire [OUT_W-2:0] tri_half_u;
    generate
        if (PHASE_W >= OUT_W) begin : gen_tri_narrow
            assign tri_half_u = phase[PHASE_W-2 -: (OUT_W-1)];
        end else begin : gen_tri_wide
            assign tri_half_u = {phase[PHASE_W-2:0], {(OUT_W - PHASE_W){1'b0}}};
        end
    endgenerate

    wire [OUT_W-2:0] tri_ramp_u = phase[PHASE_W-1] ? ~tri_half_u : tri_half_u;
    wire signed [OUT_W:0] tri_wide = $signed({2'b00, tri_ramp_u}) - $signed({2'b00, 1'b1, {(OUT_W-2){1'b0}}});
    wire signed [OUT_W-1:0] tri_diff = tri_wide[OUT_W-1:0];
    wire signed [OUT_W-1:0] tri_s = tri_diff[OUT_W-1:0];
    wire [1:0] _unused_vco_msb = {saw_wide[OUT_W], tri_wide[OUT_W]};

    always @(*) begin
        case (wave_sel)
            2'd0:    wave_out = saw_s;
            2'd1:    wave_out = sq_s;
            2'd2:    wave_out = tri_s;
            default: wave_out = saw_s;
        endcase
    end

endmodule
