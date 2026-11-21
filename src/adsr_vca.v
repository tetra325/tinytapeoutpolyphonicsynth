// adsr_vca.v
// Multiplier-free ADSR envelope generator + VCA.
module adsr_vca #(
    parameter AUDIO_W  = 12,
    parameter RATE_DIV = 64
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        sample_tick,
    input  wire                        gate,
    input  wire [2:0]                  atk_shift,
    input  wire [2:0]                  dec_shift,
    input  wire [2:0]                  sustain_3b,
    input  wire [2:0]                  rel_shift,
    input  wire signed [AUDIO_W-1:0]   audio_in,
    output wire signed [AUDIO_W-1:0]   audio_out,
    output wire [15:0]                 env_out
);

    wire _unused_rel = ^rel_shift;

    localparam [2:0] S_IDLE    = 3'd0,
                     S_ATTACK  = 3'd1,
                     S_DECAY   = 3'd2,
                     S_SUSTAIN = 3'd3,
                     S_RELEASE = 3'd4;

    reg [2:0]  state;
    reg [15:0] env;
    reg [$clog2(RATE_DIV)-1:0] rate_cnt;

    wire rate_tick = sample_tick && ({26'd0, rate_cnt} == (RATE_DIV - 1));
    wire [15:0] sustain_target = {sustain_3b, 13'd0};

    wire [15:0] atk_rem  = 16'hF800 - env;
    wire [15:0] atk_step = (atk_rem >> atk_shift) + 16'd1;

    wire [15:0] dec_diff = (env > sustain_target) ? (env - sustain_target) : 16'd0;
    wire [15:0] dec_step = (dec_diff >> dec_shift) + 16'd1;

    always @(posedge clk) begin
        if (!rst_n) begin
            rate_cnt <= {($clog2(RATE_DIV)){1'b0}};
        end else if (sample_tick) begin
            if (rate_tick)
                rate_cnt <= {($clog2(RATE_DIV)){1'b0}};
            else
                rate_cnt <= rate_cnt + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
            env   <= 16'd0;
        end else if (!gate) begin
            if (env == 16'd0) begin
                state <= S_IDLE;
            end else begin
                state <= S_RELEASE;
                if (rate_tick) begin
                    if (env <= 16'd256)
                        env <= 16'd0;
                    else
                        env <= env - 16'd256;
                end
            end
        end else begin
            if (state == S_IDLE || state == S_RELEASE) begin
                state <= S_ATTACK;
            end

            if (rate_tick) begin
                case (state)
                    S_ATTACK: begin
                        if (env >= 16'hF800 || atk_step >= atk_rem) begin
                            env   <= 16'hF800;
                            state <= S_DECAY;
                        end else begin
                            env <= env + atk_step;
                        end
                    end

                    S_DECAY: begin
                        if (env <= sustain_target || dec_step >= dec_diff) begin
                            env   <= sustain_target;
                            state <= S_SUSTAIN;
                        end else begin
                            env <= env - dec_step;
                        end
                    end

                    S_SUSTAIN: begin
                        if (env > sustain_target) begin
                            if (dec_step >= dec_diff)
                                env <= sustain_target;
                            else
                                env <= env - dec_step;
                        end else begin
                            env <= sustain_target;
                        end
                    end

                    default: begin
                        state <= S_ATTACK;
                    end
                endcase
            end
        end
    end

    // Multiplier-free VCA using top 8 bits of envelope (env[15:8])
    wire signed [AUDIO_W:0] s1 = env[15] ? ({{1{audio_in[AUDIO_W-1]}}, audio_in} >>> 1) : {(AUDIO_W+1){1'b0}};
    wire signed [AUDIO_W:0] s2 = env[14] ? ({{1{audio_in[AUDIO_W-1]}}, audio_in} >>> 2) : {(AUDIO_W+1){1'b0}};
    wire signed [AUDIO_W:0] s3 = env[13] ? ({{1{audio_in[AUDIO_W-1]}}, audio_in} >>> 3) : {(AUDIO_W+1){1'b0}};
    wire signed [AUDIO_W:0] s4 = env[12] ? ({{1{audio_in[AUDIO_W-1]}}, audio_in} >>> 4) : {(AUDIO_W+1){1'b0}};
    wire signed [AUDIO_W:0] s5 = env[11] ? ({{1{audio_in[AUDIO_W-1]}}, audio_in} >>> 5) : {(AUDIO_W+1){1'b0}};
    wire signed [AUDIO_W:0] s6 = env[10] ? ({{1{audio_in[AUDIO_W-1]}}, audio_in} >>> 6) : {(AUDIO_W+1){1'b0}};
    wire signed [AUDIO_W:0] s7 = env[9]  ? (audio_in >>> 7) : {(AUDIO_W+1){1'b0}};
    wire signed [AUDIO_W:0] s8 = env[8]  ? (audio_in >>> 8) : {(AUDIO_W+1){1'b0}};

    wire signed [AUDIO_W+3:0] vca_sum = {{3{s1[AUDIO_W]}}, s1} + {{3{s2[AUDIO_W]}}, s2} + {{3{s3[AUDIO_W]}}, s3} + {{3{s4[AUDIO_W]}}, s4} + {{3{s5[AUDIO_W]}}, s5} + {{3{s6[AUDIO_W]}}, s6} + {{3{s7[AUDIO_W]}}, s7} + {{3{s8[AUDIO_W]}}, s8};

    localparam signed [AUDIO_W-1:0] MAX_POS = {1'b0, {(AUDIO_W-1){1'b1}}};
    localparam signed [AUDIO_W-1:0] MAX_NEG = {1'b1, {(AUDIO_W-1){1'b0}}};

    assign audio_out = (vca_sum > $signed({{(4){1'b0}}, MAX_POS})) ? MAX_POS :
                       (vca_sum < $signed({{(4){1'b1}}, MAX_NEG})) ? MAX_NEG :
                       vca_sum[AUDIO_W-1:0];

    assign env_out = env;

endmodule
