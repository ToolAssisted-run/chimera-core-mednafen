# chimera-core-mednafen

A core for [Chimera](https://github.com/ToolAssisted-run/chimera), the
frontend for tool-assisted speedruns, with four systems Chimera had none of:
the **Sega Saturn**, the **Virtual Boy**, the **PC-FX** and the **Atari
Lynx**, and with the Saturn's arcade board, the **Sega ST-V**. It is built on [Mednafen](https://mednafen.github.io/) 1.32.1 and
produces one file, `mednafen.chimeraCore`, that goes in Chimera's `Cores`
folder. Mednafen's other systems are not in it: Chimera has other cores for
them.

## Status

New, and not published yet.

Each machine has run games, and for each the sandboxed core gives the same
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
- **ST-V**: Virtua Fighter Remix, Die Hard Arcade, Shienryu (its picture
  turned upright) and Tatacot (played with a hammer) were played from a coin.
  Mednafen knows 64 ST-V games. Of the 61 whose ROM sets were tried, 47
  showed the game or its demonstration after a minute, and the others did
  not get that far: [docs/PLAN.md](docs/PLAN.md) lists them. Also save data.
- On Windows, Chimera's headless runner plays a movie of a game of each
  machine and ends on the same picture as on Linux (and the same memory, or
  for the ST-V the same save data). Chimera's window on Windows opens and
  runs a project of each of the four systems; it was not tried there with
  the ST-V.

## What you bring

- **Saturn**: a game as a `.cue` file with its track files beside it, or as
  a `.chd` file, and the BIOS of the game's region. The core reads the disc and Chimera's
  Firmware page asks for the one it needs: the Japanese BIOS (usually
  `sega_101.bin`) for games of Japan and Taiwan, the North American and
  European one (usually `mpr-17933.bin`) for the others.
- **Virtual Boy**: a `.vb` or `.vboy` cartridge file. It needs no BIOS.
- **PC-FX**: a `.cue` or `.chd` disc and the BIOS, `pcfx.rom`.
- **Lynx**: a `.lnx` cartridge file and the boot ROM, `lynxboot.img`.
- **ST-V**: the game's ROM set, a `.zip` of its ROM files under the names
  MAME gives them (`vfremix.zip`), and MAME's set of the board's BIOS files,
  `stvbios.zip`, which Chimera's Firmware page asks for. The zip has to hold
  every file of the game. The core takes the BIOS of the game's region out
  of the set by its contents, so a set from any version of MAME works.

## Buttons and settings

Each system has the controls of everything Mednafen can plug into it. A
project shows the ones of what is plugged in: by default a pad in port 1
and nothing in the other ports. A second player's pad is put in with the
Port 2 setting.

- **Saturn**: twelve ports (two, or up to twelve with multitaps), and for
  each a pad, a 3D pad, a mouse, a steering wheel, a mission stick or two, a
  light gun, and on ports 1 and 2 a keyboard. `P1 A` is the A of whatever
  pad is in port 1. Reset, and the drive: Previous Disc and Next Disc move a
  selector over the project's discs, and Disc Swap is the lid, up for as
  long as it is held.
- **ST-V**: for each of two players a stick, Button 1 to Button 6 and Start,
  and the cabinet's Coin, Test, Service and Pause. The controls are the
  game's own: a game played with a hammer has Hammer X, Hammer Y and Hammer
  Hit instead of the sticks. In Radiant Silvergun, Buttons 4, 5 and 6 are
  the pairs of the first three, as Mednafen has them. The Region setting
  picks the BIOS: the game's own region, Japan, North America or Europe.
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
ST-V's memory is read the same way. The other systems' RAM is a memory
domain.

Save data stays inside the machine, where a savestate holds it. Emulator >
Export Save Data... writes it to files (the Saturn's `.bkr` and `.bcr`, the
PC-FX's `.sav` and `.fxb`, a Virtual Boy cartridge's `.sav`, the ST-V's
`.bkr` and `.seep`), and a
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
