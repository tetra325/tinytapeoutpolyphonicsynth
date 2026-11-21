# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


async def send_midi_byte(dut, byte_val, clks_per_bit=384):
    # uio_in[0] idle high (1); start bit low (0); 8 data bits LSB first; stop bit high (1)
    cur = int(dut.uio_in.value)
    dut.uio_in.value = cur & ~1
    await ClockCycles(dut.clk, clks_per_bit)
    for i in range(8):
        bit = (byte_val >> i) & 1
        cur = (int(dut.uio_in.value) & ~1) | bit
        dut.uio_in.value = cur
        await ClockCycles(dut.clk, clks_per_bit)
    cur = int(dut.uio_in.value) | 1
    dut.uio_in.value = cur
    await ClockCycles(dut.clk, clks_per_bit)


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")
    # 12 MHz clock -> ~83.333 ns period
    clock = Clock(dut.clk, 84, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 1  # MIDI line idle high on uio_in[0]
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

    # After reset, any_gate (uo_out[3]) should be 0 and BCLK/LRCK should toggle
    assert ((int(dut.uo_out.value) >> 3) & 1) == 0

    # Send MIDI Note On ch 0, note 60 (0x3C), vel 100 (0x64) at 31250 baud (12e6 / 31250 = 384 clks/bit)
    for b in (0x90, 0x3C, 0x64):
        await send_midi_byte(dut, b, clks_per_bit=384)

    await ClockCycles(dut.clk, 512)
    assert ((int(dut.uo_out.value) >> 3) & 1) == 1

    # Send MIDI Note Off ch 0, note 60 (0x3C), vel 0 (0x00)
    for b in (0x80, 0x3C, 0x00):
        await send_midi_byte(dut, b, clks_per_bit=384)

    await ClockCycles(dut.clk, 16)
