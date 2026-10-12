#!/usr/bin/env python3
"""Writes a Virtual Boy program for the tests: a cartridge of 1024 bytes that
this script assembles itself, so the tests have a game they may carry
anywhere (a public CI runner has no game and may be given none).

The program counts in a loop and copies what it reads of the pad into the
console's RAM, where the tests look:

    WRAM + 0   a 32-bit counter, one more each time round the loop
    WRAM + 4   the pad's low byte  (register 0x02000010)
    WRAM + 5   the pad's high byte (register 0x02000014)

It draws nothing: the picture stays black. What it proves is that the
processor runs, that the pad reaches the game, and that the game's reads of
the pad are seen (a frame with a read is not a lag frame).

usage: make-vb-program.py <out.vb> [--no-pad]

--no-pad leaves the two reads of the pad out, for the test that every frame
of such a program is counted as a lag frame.
"""
import struct
import sys

R0, WRAM, IO, COUNT, PAD, ROM, LOOP = 0, 1, 2, 3, 4, 5, 6


def fmt(op, reg2, low5):
    return struct.pack("<H", (op << 10) | (reg2 << 5) | low5)


def movhi(imm, reg1, reg2):      # reg2 = reg1 + (imm << 16)
    return fmt(0b101111, reg2, reg1) + struct.pack("<H", imm)


def movea(imm, reg1, reg2):      # reg2 = reg1 + imm
    return fmt(0b101000, reg2, reg1) + struct.pack("<H", imm)


def add_imm(imm5, reg2):         # reg2 += imm5
    return fmt(0b010001, reg2, imm5)


def st_w(reg2, disp, reg1):      # [reg1 + disp] = reg2, 32 bits
    return fmt(0b110111, reg2, reg1) + struct.pack("<H", disp)


def st_b(reg2, disp, reg1):      # [reg1 + disp] = reg2, 8 bits
    return fmt(0b110100, reg2, reg1) + struct.pack("<H", disp)


def ld_b(disp, reg1, reg2):      # reg2 = [reg1 + disp], 8 bits
    return fmt(0b110000, reg2, reg1) + struct.pack("<H", disp)


def jmp(reg1):                   # go to the address in reg1
    return fmt(0b000110, 0, reg1)


def main():
    size = 1024
    start = movhi(0x0500, R0, WRAM) + movhi(0x0200, R0, IO) + movhi(0x0700, R0, ROM)
    start += movea(len(start) + 4, ROM, LOOP)      # the loop begins after this instruction
    loop = add_imm(1, COUNT) + st_w(COUNT, 0, WRAM)
    if "--no-pad" not in sys.argv:
        loop += ld_b(0x10, IO, PAD) + st_b(PAD, 4, WRAM) + ld_b(0x14, IO, PAD) + st_b(PAD, 5, WRAM)
    loop += jmp(LOOP)
    # the processor starts at 0xFFFFFFF0, the cartridge's last 16 bytes
    vector = movhi(0x0700, R0, ROM) + jmp(ROM)
    rom = bytearray(size)
    rom[0:len(start + loop)] = start + loop
    rom[size - 16:size - 16 + len(vector)] = vector
    with open(sys.argv[1], "wb") as f:
        f.write(rom)


if __name__ == "__main__":
    main()
