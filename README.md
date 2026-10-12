# chimera-core-mednafen

A core for [Chimera](https://github.com/ToolAssisted-run/chimera), the
frontend for tool-assisted speedruns, with four systems Chimera had none of:
the **Sega Saturn**, the **Virtual Boy**, the **PC-FX** and the **Atari
Lynx**. It is built on [Mednafen](https://mednafen.github.io/) 1.32.1 and
produces one file, `mednafen.chimeraCore`, that goes in Chimera's `Cores`
folder. Mednafen's other systems are not in it: Chimera has other cores for
them.

## Status

New, and not published yet.

- **Saturn**: two games have been run, Virtua Fighter Remix (USA) and Virtua
  Fighter 2 (Japan). Picture, sound, pads, savestates, save data, changing
  discs and lag frames work, and the sandboxed core gives the same results
  as a plain native build on Linux.
- **Virtual Boy**: it has only run a small program the tests assemble. No
  game has been tried.
- **PC-FX**, **Lynx**: they build. Neither has run anything: no game of
  theirs was at hand.
- Not tried on Windows yet.
- Not there: CHD disc images (a disc is a `.cue` with its track files), the
  Saturn's ST-V arcade board, save data of the PC-FX and of Virtual Boy
  cartridges, and the Saturn's video and sound memory in RAM Watch.

## What you bring

- **Saturn**: a game as a `.cue` file with its track files beside it, and
  the BIOS of the game's region. The core reads the disc and Chimera's
  Firmware page asks for the one it needs: the Japanese BIOS (usually
  `sega_101.bin`) for games of Japan and Taiwan, the North American and
  European one (usually `mpr-17933.bin`) for the others.
- **Virtual Boy**: a `.vb` or `.vboy` cartridge file. It needs no BIOS.
- **PC-FX**: a `.cue` disc and the BIOS, `pcfx.rom`.
- **Lynx**: a `.lnx` cartridge file and the boot ROM, `lynxboot.img`.

## Buttons and settings

Each system has the controls of everything Mednafen can plug into it. A
project shows the ones of what is plugged in: by default a pad in each of
the console's own ports.

- **Saturn**: twelve ports (two, or up to twelve with multitaps), and for
  each a pad, a 3D pad, a mouse, a steering wheel, a mission stick or two, a
  light gun, and on ports 1 and 2 a keyboard. `P1 A` is the A of whatever
  pad is in port 1. Reset, and the drive: Previous Disc and Next Disc move a
  selector over the project's discs, and Disc Swap is the lid, up for as
  long as it is held.
- **Settings**: Mednafen's own, under Mednafen's names. For the Saturn: the
  region, the cartridge (backup memory, 1 MB or 4 MB RAM, and others), the
  multitaps, what is in each port, the clock the console starts with, and
  how the picture is shown. For the Virtual Boy: how the two eyes' pictures
  are shown, and the processor's accuracy.

Settings that are part of the machine are recorded in a project: a movie
made with one value does not play back with another. Each setting's
description says which kind it is.

RAM Watch and RAM Search read the Saturn's two work RAMs through "System
Bus", at the addresses a game uses (`0x00200000` and `0x06000000`), and the
other systems' RAM as a memory domain.

## Building and testing

[docs/BUILDING.md](docs/BUILDING.md) has every step. [docs/PLAN.md](docs/PLAN.md)
is the design log: what was decided, why, and what was measured.

## Licence

This repository's own code is MIT. Mednafen is under the GNU General Public
License version 2 or later, and so are the patches to it here and the
program in the built package. The package carries the licence texts of
everything in it. It contains no BIOS and no game. See [LICENSE](LICENSE).
