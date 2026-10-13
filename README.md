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

Each system has run games, and for each the sandboxed core gives the same
results as a plain native build: picture, sound, pads, lag frames and
savestates.

- **Saturn**: Virtua Fighter Remix (USA) and Virtua Fighter 2 (Japan). Also
  save data, changing discs, and CHD disc images.
- **Virtual Boy**: Virtual Boy Wario Land, Mario Clash and Red Alarm. Also
  save data.
- **PC-FX**: Last Imperial Prince (Japan), both discs. Also save data (the
  console's backup memory and the memory pack), changing discs, and a CHD
  disc image.
- **Lynx**: California Games and Chip's Challenge.
- On Windows, Chimera's headless runner plays a movie of a game of each
  system and ends on the same memory and the same picture as on Linux, and
  Chimera's window opens and runs a project of each.
- Not there: the Saturn's ST-V arcade board (no game of it was at hand to
  test with).

## What you bring

- **Saturn**: a game as a `.cue` file with its track files beside it, or as
  a `.chd` file, and the BIOS of the game's region. The core reads the disc and Chimera's
  Firmware page asks for the one it needs: the Japanese BIOS (usually
  `sega_101.bin`) for games of Japan and Taiwan, the North American and
  European one (usually `mpr-17933.bin`) for the others.
- **Virtual Boy**: a `.vb` or `.vboy` cartridge file. It needs no BIOS.
- **PC-FX**: a `.cue` or `.chd` disc and the BIOS, `pcfx.rom`.
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

RAM Watch and RAM Search read the Saturn's memory through "System Bus", at
the addresses a game uses: the two work RAMs (`0x00200000` and
`0x06000000`), the sound processor's RAM (`0x05A00000`), the two video
processors' memories (`0x05C00000` and `0x05E00000`), the colour memory
(`0x05F00000`), and a RAM cartridge's when one is in (`0x02400000`). The
other systems' RAM is a memory domain.

Save data stays inside the machine, where a savestate holds it. Emulator >
Export Save Data... writes it to files (the Saturn's `.bkr` and `.bcr`, the
PC-FX's `.sav` and `.fxb`, a Virtual Boy cartridge's `.sav`), and a
project's Save data slot takes such files, or Mednafen's own, to start from.

The sound is 44.1 kHz stereo: the rate of the Saturn's sound chip and of a
CD's audio.

## Building and testing

[docs/BUILDING.md](docs/BUILDING.md) has every step. [docs/PLAN.md](docs/PLAN.md)
is the design log: what was decided, why, and what was measured.

## Licence

This repository's own code is MIT. Mednafen is under the GNU General Public
License version 2 or later, and so are the patches to it here and the
program in the built package. The package carries the licence texts of
everything in it. It contains no BIOS and no game. See [LICENSE](LICENSE).
