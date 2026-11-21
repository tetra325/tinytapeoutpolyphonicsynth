<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This project implements a 6-voice polyphonic, multiplier-free subtractive synthesizer designed for a `2x2` GF 26c (`gf180mcuD`) tile:

- **MIDI Receiver (`midi_rx.v`):** Samples 31,250-baud serial MIDI bytes on `uio_in[0]` (`midi_rx_in`).
- **Polyphonic Note Allocator (`poly_note_ctrl.v`):** Allocates up to 6 voices using note reuse, first free voice, or lowest-envelope voice stealing, supporting Note On (`0x9n`, velocity greater than 0), Note Off (`0x8n` or `0x9n` with velocity 0), MIDI running status, and interleaved real-time messages (`>= 0xF8`).
- **Oscillators & Envelopes (`vco.v`, `adsr_vca.v`):** Each voice runs a phase-accumulator oscillator (`PHASE_W = 20`, `DATA_W = 12`) with selectable Saw, Square, and Triangle waveforms, paired with an envelope generator and shift-based VCA (`ui_in[1:0]`, `uio_in[3:1]`, `uio_in[6:4]`).
- **Shift-and-Add Mix & SVF (`synth_top.v`, `vcf_svf.v`):** Sums the 6 voices without multipliers using an arithmetic right shift (`>>> 3`) for headroom, then filters the mix through a state-variable filter (`cutoff_shift` on `ui_in[4:2]`, `res_shift` on `ui_in[7:5]`).
- **I2S Output (`i2s_tx.v`):** Streams audio out on `uo_out[0]` (`i2s_sdata`), `uo_out[1]` (`i2s_bclk`), and `uo_out[2]` (`i2s_lrck`), with `uo_out[3]` indicating active gate state.

## How to test

1. Supply a 12 MHz clock on `clk` and assert active-low reset `rst_n` (`0` then `1`) with `ena = 1`.
2. Configure waveform (`ui_in[1:0]`), filter cutoff shift (`ui_in[4:2]`), filter resonance shift (`ui_in[7:5]`), attack shift (`uio_in[3:1]`), and decay shift (`uio_in[6:4]`).
3. Send 31,250-baud serial MIDI Note On / Note Off frames into `uio_in[0]` (via a proper MIDI optocoupler receiver circuit on hardware or a UART stimulus in simulation).
4. Observe `uo_out[3]` (`any_gate`) going high while notes are held and monitor `uo_out[0..2]` (`i2s_sdata`, `i2s_bclk`, `i2s_lrck`) with an I2S DAC or logic analyzer.
