// midi_rx.v
// Asynchronous serial receiver for standard MIDI (31250 baud, 8N1).
// At CLK_HZ = 12_000_000 and BAUD = 31250: CLKS_PER_BIT = 384.
module midi_rx #(
    parameter integer CLK_HZ = 12_000_000,
    parameter integer BAUD   = 31250
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       midi_rx_in, // Idle high (1'b1), start bit low (1'b0)
    output reg  [7:0] rx_byte,
    output reg        byte_valid
);

    localparam integer CLKS_PER_BIT = (CLK_HZ + (BAUD / 2)) / BAUD;
    localparam integer HALF_BIT     = CLKS_PER_BIT / 2;

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    // 2-stage synchronizer to avoid metastability on asynchronous MIDI input
    reg sync_0, sync_1, prev_rx;
    always @(posedge clk) begin
        if (!rst_n) begin
            sync_0  <= 1'b1;
            sync_1  <= 1'b1;
            prev_rx <= 1'b1;
        end else begin
            sync_0  <= midi_rx_in;
            sync_1  <= sync_0;
            prev_rx <= sync_1;
        end
    end

    wire start_edge = (prev_rx == 1'b1) && (sync_1 == 1'b0);

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_byte;

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            clk_cnt    <= 16'd0;
            bit_idx    <= 3'd0;
            shift_byte <= 8'd0;
            rx_byte    <= 8'd0;
            byte_valid <= 1'b0;
        end else begin
            byte_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (start_edge) begin
                        state <= S_START;
                    end
                end

                S_START: begin
                    if (clk_cnt == HALF_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        if (sync_1 == 1'b0) begin
                            // Valid start bit mid-point; move to bit 0
                            state <= S_DATA;
                        end else begin
                            // False glitch
                            state <= S_IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        shift_byte[bit_idx] <= sync_1; // LSB first
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state   <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        if (sync_1 == 1'b1) begin
                            rx_byte    <= shift_byte;
                            byte_valid <= 1'b1;
                        end
                        state <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
