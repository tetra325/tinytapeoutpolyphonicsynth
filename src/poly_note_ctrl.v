// poly_note_ctrl.v
// 6-voice polyphonic MIDI note allocator (multiplier-free LUT).
// Supports Note On (0x9n, vel>0), Note Off (0x8n or 0x9n vel==0),
// real-time filtering (>=0xF8), and MIDI running status.
module poly_note_ctrl #(
    parameter integer VOICES  = 6,
    parameter integer PHASE_W = 20
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire [7:0]                  rx_byte,
    input  wire                        byte_valid,
    input  wire [VOICES*16-1:0]        env_bus,
    output reg  [VOICES-1:0]           voice_gate,
    output wire [VOICES*PHASE_W-1:0]   phase_inc_bus,
    output wire                        any_gate
);

    reg [7:0] status;
    reg [6:0] data1;
    reg       have_data1;

    reg [6:0]         note_table [0:VOICES-1];
    reg [PHASE_W-1:0] inc_table  [0:VOICES-1];

    assign any_gate = |voice_gate;

    genvar idx_g;
    generate
        for (idx_g = 0; idx_g < VOICES; idx_g = idx_g + 1) begin : gen_inc_bus
            assign phase_inc_bus[idx_g*PHASE_W +: PHASE_W] = inc_table[idx_g];
        end
    endgenerate

    function [PHASE_W-1:0] note_to_inc;
        input [6:0] note;
        begin
            case (note)
                // Octave 2
                7'd36: note_to_inc = 20'd1463;  // C2  (~65.41 Hz)
                7'd38: note_to_inc = 20'd1642;  // D2  (~73.42 Hz)
                7'd40: note_to_inc = 20'd1843;  // E2  (~82.41 Hz)
                7'd41: note_to_inc = 20'd1953;  // F2  (~87.31 Hz)
                7'd43: note_to_inc = 20'd2192;  // G2  (~98.00 Hz)
                7'd45: note_to_inc = 20'd2461;  // A2  (~110.00 Hz)
                7'd47: note_to_inc = 20'd2762;  // B2  (~123.47 Hz)
                // Octave 3
                7'd48: note_to_inc = 20'd2926;  // C3  (~130.81 Hz)
                7'd49: note_to_inc = 20'd3100;  // C#3 (~138.59 Hz)
                7'd50: note_to_inc = 20'd3285;  // D3  (~146.83 Hz)
                7'd51: note_to_inc = 20'd3480;  // D#3 (~155.56 Hz)
                7'd52: note_to_inc = 20'd3687;  // E3  (~164.81 Hz)
                7'd53: note_to_inc = 20'd3906;  // F3  (~174.61 Hz)
                7'd54: note_to_inc = 20'd4138;  // F#3 (~185.00 Hz)
                7'd55: note_to_inc = 20'd4385;  // G3  (~196.00 Hz)
                7'd56: note_to_inc = 20'd4645;  // G#3 (~207.65 Hz)
                7'd57: note_to_inc = 20'd4921;  // A3  (~220.00 Hz)
                7'd58: note_to_inc = 20'd5214;  // A#3 (~233.08 Hz)
                7'd59: note_to_inc = 20'd5524;  // B3  (~246.94 Hz)
                // Octave 4
                7'd60: note_to_inc = 20'd5853;  // C4  (~261.63 Hz)
                7'd61: note_to_inc = 20'd6201;  // C#4 (~277.18 Hz)
                7'd62: note_to_inc = 20'd6569;  // D4  (~293.66 Hz)
                7'd63: note_to_inc = 20'd6960;  // D#4 (~311.13 Hz)
                7'd64: note_to_inc = 20'd7373;  // E4  (~329.63 Hz)
                7'd65: note_to_inc = 20'd7813;  // F4  (~349.23 Hz)
                7'd66: note_to_inc = 20'd8277;  // F#4 (~369.99 Hz)
                7'd67: note_to_inc = 20'd8770;  // G4  (~392.00 Hz)
                7'd68: note_to_inc = 20'd9291;  // G#4 (~415.30 Hz)
                7'd69: note_to_inc = 20'd9842;  // A4  (440.00 Hz)
                7'd70: note_to_inc = 20'd10428; // A#4 (~466.16 Hz)
                7'd71: note_to_inc = 20'd11047; // B4  (~493.88 Hz)
                // Octave 5
                7'd72: note_to_inc = 20'd11706; // C5  (~523.25 Hz)
                7'd73: note_to_inc = 20'd12402; // C#5 (~554.37 Hz)
                7'd74: note_to_inc = 20'd13139; // D5  (~587.33 Hz)
                7'd75: note_to_inc = 20'd13920; // D#5 (~622.25 Hz)
                7'd76: note_to_inc = 20'd14747; // E5  (~659.25 Hz)
                7'd77: note_to_inc = 20'd15625; // F5  (~698.46 Hz)
                7'd78: note_to_inc = 20'd16555; // F#5 (~739.99 Hz)
                7'd79: note_to_inc = 20'd17539; // G5  (~783.99 Hz)
                7'd80: note_to_inc = 20'd18582; // G#5 (~830.61 Hz)
                7'd81: note_to_inc = 20'd19685; // A5  (~880.00 Hz)
                7'd82: note_to_inc = 20'd20855; // A#5 (~932.33 Hz)
                7'd83: note_to_inc = 20'd22095; // B5  (~987.77 Hz)
                7'd84: note_to_inc = 20'd23411; // C6  (~1046.50 Hz)
                default: note_to_inc = 20'd9842; // Fallback A4
            endcase
        end
    endfunction

    integer i;
    reg [2:0]  alloc_idx;
    reg        found_match;
    reg        found_free;
    reg [15:0] min_env;

    always @(*) begin
        alloc_idx   = 3'd0;
        found_match = 1'b0;
        found_free  = 1'b0;
        min_env     = 16'hFFFF;

        // 1. Reuse voice already playing this note
        for (i = 0; i < VOICES; i = i + 1) begin
            if (!found_match && voice_gate[i] && (note_table[i] == data1)) begin
                alloc_idx   = i[2:0];
                found_match = 1'b1;
            end
        end

        // 2. Otherwise pick first ungated voice
        if (!found_match) begin
            for (i = 0; i < VOICES; i = i + 1) begin
                if (!found_free && !voice_gate[i]) begin
                    alloc_idx  = i[2:0];
                    found_free = 1'b1;
                end
            end
        end

        // 3. Otherwise steal voice with lowest current envelope
        if (!found_match && !found_free) begin
            for (i = 0; i < VOICES; i = i + 1) begin
                if (env_bus[i*16 +: 16] < min_env) begin
                    min_env   = env_bus[i*16 +: 16];
                    alloc_idx = i[2:0];
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            status     <= 8'd0;
            data1      <= 7'd0;
            have_data1 <= 1'b0;
            voice_gate <= {VOICES{1'b0}};
            for (i = 0; i < VOICES; i = i + 1) begin
                note_table[i] <= 7'd69;
                inc_table[i]  <= 20'd9842;
            end
        end else if (byte_valid) begin
            if (rx_byte[7]) begin
                // System Real-Time messages (0xF8..0xFF) can appear anywhere without
                // altering running status or an in-progress message.
                if (rx_byte < 8'hF8) begin
                    status     <= rx_byte;
                    have_data1 <= 1'b0;
                end
            end else if (status[7]) begin
                if (!have_data1) begin
                    data1      <= rx_byte[6:0];
                    have_data1 <= 1'b1;
                end else begin
                    have_data1 <= 1'b0;

                    // Note On (velocity > 0)
                    if (status[7:4] == 4'h9 && rx_byte[6:0] != 7'd0) begin
                        voice_gate[alloc_idx] <= 1'b1;
                        note_table[alloc_idx] <= data1;
                        inc_table[alloc_idx]  <= note_to_inc(data1);
                    end
                    // Note Off (0x8n or 0x9n with velocity == 0)
                    else if (status[7:4] == 4'h8 || (status[7:4] == 4'h9 && rx_byte[6:0] == 7'd0)) begin
                        for (i = 0; i < VOICES; i = i + 1) begin
                            if (note_table[i] == data1) begin
                                voice_gate[i] <= 1'b0;
                            end
                        end
                    end
                end
            end
        end
    end

endmodule
