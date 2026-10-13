# The plan

This core is Mednafen for Chimera, for the systems BizHawk runs with
Mednafen that Chimera has no core for: the Sega Saturn, the Virtual Boy, the
PC-FX and the Atari Lynx. The owner asked for it on 2026-10-12 ("let's start
with the Mednafen core"), as the first step of having every system BizHawk
supports in Chimera. This page says what was found before any code, what was
decided, and what each step has to prove. It is updated as steps are done.

## What was read (2026-10-12)

- **Mednafen 1.32.1**, the newest release (2024-04). Mednafen is published
  as release archives only. It has no public repository.
- **BizHawk's Mednafen cores** ("nyma": TASEmulators/BizHawk at ab81ea2,
  `waterbox/nyma`). BizHawk compiles Mednafen's source files directly, with
  no configure step, one sandboxed core a system, behind one small generic
  frontend (`NymaCore.cpp`): it calls the system's `Load` and `Emulate`,
  hands Mednafen a block of bytes for each controller port, and reads the
  systems' own descriptions of their ports, settings and picture layers.
  Its copy of Mednafen (TASEmulators/mednafen) carries 25 commits of changes:
  the Saturn's picture is drawn without its helper thread, controller reads
  set a lag flag, and a few others.
- That copy's "upstream" branch is NOT the official source: its include
  paths were rewritten (`<mednafen/...>` to `<src/...>`), 269 files differ
  from the official archive. So it is not used here.

## The eight questions (docs/new-core.md in chimera)

1. **A new core?** Yes. Chimera has no Saturn, Virtual Boy, PC-FX or Lynx.
   One package, a machine each. Mednafen's other systems (PlayStation, PC
   Engine, SNES, Game Boy and so on) are already covered by other cores and
   are left out.
2. **Licence.** GPL-2.0-or-later. A core is its source with patches,
   published as a binary with its licence text: allowed.
3. **One thread on one clock?** Each system is one emulation loop with two
   exceptions to remove: the Saturn draws its picture on a helper thread
   (`ss/vdp2_render.cpp`), and Mednafen's CD reader has a read-ahead thread.
   Mednafen has a single-threaded CD reader too. The Saturn's clock chip
   takes its start time from the host: it must come from a setting.
4. **The picture.** Each system draws into memory. No GPU.
5. **A recompiler?** No. Every processor is interpreted.
6. **What the user brings.** The Saturn BIOS (`sega_101.bin` for Japan,
   `mpr-17933.bin` for America and Europe), the PC-FX BIOS (`pcfx.rom`), the
   Lynx boot ROM (`lynxboot.img`). The Virtual Boy needs none. Games: disc
   images for the Saturn and the PC-FX, cartridge files for the other two.
7. **What a public runner can test.** No BIOS may be put there, so no
   Saturn, PC-FX or Lynx machine can start on one. The Virtual Boy needs no
   BIOS: a test program the test script writes itself (a few V810
   instructions that draw and read the pad) can run there.
8. **Size.** Small machines. A Saturn disc is mounted from its file, not
   read into memory.

## The source pin

`waterbox/fetch-mednafen.sh` downloads the official archive
`mednafen-1.32.1.tar.xz` and checks its SHA-256
(de7eb94ab66212ae7758376524368a8ab208234b33796625ca630547dbc83832) before
unpacking it into `extern/mednafen`, which is not in git. A change to
Mednafen is a numbered patch in `patches/`.

## The design

- **One generic frontend** over Mednafen's own description of a system
  (`MDFNGI`): load, one frame, the ports, the settings, savestates are the
  sandbox's. The machine setting picks the system.
- **Controllers**: Mednafen describes each port's devices and every button
  and axis of each. The package's controls are generated from that
  description by a probe, per machine, and a setting per port says what is
  plugged in; Chimera hides the controls of what is not.
- **Settings**: Mednafen's own, per system, generated the same way (region,
  cartridge, and so on). Only those that are part of the machine.
- **Discs**: `.cue` with its track files first (Mednafen's own reader, the
  single-threaded one). CHD is not something Mednafen reads; other Chimera
  cores read it with libchdr, and that can be added behind Mednafen's disc
  interface.
- **Lag frames**: a frame in which the game did not read its controllers,
  as BizHawk's copy marks them.
- **Save data**: the Saturn's internal backup RAM and cartridge, the PC-FX's
  backup RAM, as files.

## What is on this machine to test with

- Saturn: Virtua Fighter Remix (USA) and Virtua Fighter 2 (Japan), and the
  BIOS files. Both run; the second starts with the Japanese BIOS and in the
  console's 704x480 mode.
- Lynx: the boot ROM, and since 2026-10-13 California Games and Chip's
  Challenge.
- PC-FX: the BIOS (`pcfx.rom`), and since 2026-10-13 Last Imperial Prince
  (Japan), both discs.
- Virtual Boy: since 2026-10-13 Virtual Boy Wario Land, Mario Clash and Red
  Alarm. The tests also assemble a small program for it
  (`tests/make-vb-program.py`), which runs where no game may be.

Until 2026-10-13 only the Saturn had games here; the sections below that are
dated 2026-10-12 say so of the other three.

## Steps

| Step | What | Proof | State |
|---|---|---|---|
| 1 | Native build of the four systems and the frontend; the Saturn boots a game | Picture, sound, a controller press changes the picture | done 2026-10-12: Virtua Fighter Remix, BIOS logo, attract fight, Start changes the picture |
| 2 | The same in the sandbox, with the Saturn's helper thread gone | The reference and the sandbox give the same digests, frame by frame; savestates | done 2026-10-12: 1,500 frames the same natively, in the sandbox, with a state saved and loaded every frame, with the state moved to a new sandbox, and after going back to a kept state |
| 3 | Controllers and settings generated from Mednafen's descriptions; the package | Chimera's package checks; a project run by Chimera's engine | done 2026-10-12: 743 buttons and 232 axes over the four systems, 58 settings; Chimera's package checks pass (18 of 18); a project of Virtua Fighter Remix with its BIOS as firmware plays a movie in Chimera's engine and the movie's presses reach the game |
| 4 | Virtual Boy, PC-FX, Lynx with games | Each boots a game the same natively and in the sandbox | done 2026-10-13: see "Games for the other three systems" below |
| 5 | Save data, lag frames, disc change, CHD | Tests for each | done 2026-10-12: lag frames (all four systems), memory for RAM Watch and RAM Search, the Saturn's save data, the drive's lid and disc selector, CHD images |
| 6 | Windows, CI (a self-made Virtual Boy program), documents | The test script on a runner | done 2026-10-12 except a run on a CI runner: the test script (32 tests), the window test (4), README, AGENTS.md, the CI workflow (never run: the repository is not published; a fresh clone builds and passes the 13 tests that need no file). Windows: Chimera's headless runner plays the Virtual Boy project and a 1,500-frame Saturn movie with presses and ends on the same RAM and the same pictures as Linux |
| 7 | Publishing | The owner's word | on hold by the owner (2026-10-12) |

## What the first two steps found

- **Mednafen refuses the sandbox's code model** (a compile-time error, for
  speed). Two definitions of its own turn the refusal off.
- **zlib**: Mednafen brings none, the sandbox toolchain has none. It is a
  submodule, built for both flavors.
- **Track files** were asked for as `./name`; the sandbox knows a file by its
  plain name (patch 0003).
- **A state loaded while the game reads its disc** went a different way 165
  frames later: Mednafen skips a seek when it believes the file is in place,
  and the sandbox does not keep a file's position in a state (patch 0004).
  `run-wbx --rewind` was written to find this and is the test for it; the
  save-and-load-every-frame test cannot see it, because nothing has moved
  between the save and the load.
- Speed: the Saturn runs at about 180 frames a second in the sandbox on the
  development machine (Virtua Fighter Remix, attract mode).

## What step 3 decided

- **A control is named once for a port, whatever is plugged in.** "P1 A" is
  the A of the pad, the 3D pad, the wheel or the mission stick in port 1,
  because Mednafen gives them the same input name. A mouse's, a gun's and a
  keyboard's controls carry the device in their name ("P1 Mouse Left",
  "P1 Gun Trigger", "P1 Key F1"). What a device itself calls a shared control
  ("L Gear Shift" for a wheel's Up) is the label Chimera shows over the
  column.
- **Every device on every port**, except keyboards, which are on ports 1
  and 2 only. That is 591 buttons and 216 axes for the Saturn; a project
  shows the ones of what is plugged in.
- **A two-way switch is a button** (held is its second position: the 3D
  pad's analog mode, a mission stick's autofire switches, the PC-FX pad's
  mode switches, the Virtual Boy's low battery). A switch of more positions
  is an axis that takes the position's number.
- **A stick is -32768 to 32767** and written to Mednafen as it is, so no
  value Mednafen can take is out of reach. A light gun's position is 0 to
  65535 across the picture.
- **Settings keep Mednafen's own names** ("ss.cart", "ss.input.port1"). Their
  types, defaults, limits and choices are read from Mednafen; what a user
  reads about each is written in `waterbox/machines.json`.
- **The Saturn's BIOS is asked for by region of the disc.** The core answers
  before the machine is built (patch 0005). The two files are mounted under
  names of this core's own, because Mednafen refuses a file named like one
  known BIOS that holds another.
- **Not done**: the Saturn's ST-V arcade board. Mednafen 1.32 has it, and
  its controls are left out of the package. No ST-V game was at hand
  (2026-10-13), and a machine that has run nothing is not added.

## What step 5 decided

- **Lag frames**: each system says when its game code is handed a pad's
  state (patch 0006). A frame without that is a lag frame.
- **Memory**: the Virtual Boy's, the PC-FX's and the Lynx's RAM are memory
  domains, from what the systems already tell Mednafen's cheat search. The
  Saturn keeps its RAM as 16-bit words in the host's byte order, so a plain
  view of it would show every pair of bytes swapped: its two work RAMs are
  read through a bus ("System Bus"), at the console's own addresses
  (0x00200000 and 0x06000000) and in the console's byte order. (The video
  chips' and the sound chip's memory joined it on 2026-10-13, below.)
- **Save data** (the Saturn): the backup memory and the backup cartridge
  stay in the machine's memory, and Mednafen's writing of save files is
  turned off (patch 0007). Export Save Data writes `saturn.bkr` and
  `saturn.bcr`, the files Mednafen itself would write, and a project's Save
  data slot takes them back by extension. (The PC-FX's and the Virtual Boy
  cartridge's saves followed on 2026-10-13, below.)
- **The Virtual Boy test program** draws nothing. It counts in RAM and
  copies the pad there, which is enough to compare the sandbox with the
  reference, to test savestates and to test lag frames, on a CI runner.
- **The drive** has three controls, named as Chimera's other disc cores
  name them: Previous Disc and Next Disc move a selector over the project's
  discs, and Disc Swap is the lid, up while held and closing on the selected
  disc (or the next one when the selector was not moved). With the lid up a
  Saturn leaves the game for its own CD screen. The drive's light is lit on
  a frame a sector was read.

## What the window test found (2026-10-12)

Chimera asked a core about a game with the game file alone: a `.cue` without
its track files, and no settings. The Saturn's firmware answer needs to read
the disc, so in Chimera's window no BIOS was asked for and the project did
not start. The headless runner, which the test script uses, mounts
everything, so the test script could not see it; the window test did.
Chimera was changed to ask with the game's files and the settings chosen so
far (chimera commit "a core is asked about a game with the game's files",
made on 2026-10-12 and not on Chimera's main when this was written). This
core's Saturn needs a Chimera with that change.

## CHD disc images (2026-10-12)

Mednafen reads a disc from a cue sheet and its track files and has no reader
for CHD. Other Chimera cores read CHD with libchdr, and so does this one
(`waterbox/chd-disc.cpp`; libchdr 0.3.0 is a submodule).

- **A CHD is shown to Mednafen's own cue reader as the cue sheet and the
  track files it stands for.** The cue sheet is written from the CHD's track
  records, and each track file is a view of that track's sectors,
  decompressed as they are read. So there is one idea of what a disc is: the
  table of contents, the gaps, the subchannel and the lead-out are
  Mednafen's code for both formats. No Mednafen file is patched for it.
- **Audio bytes change places**: a CHD holds audio samples high byte first,
  a cue sheet's file low byte first.
- libchdr inflates with the zlib submodule and takes Zstandard from
  Mednafen's own copy, which the core links already.
- Not read: a CHD's own subchannel data (the subchannel is made by Mednafen,
  as for a cue sheet), and GD-ROM images.

Measured: a CHD made from Virtua Fighter Remix's cue sheet with chdman 0.264
(LZMA, deflate and FLAC blocks) gives, in the sandbox, the 48 digests of
RAM, picture and sound the cue sheet gives natively over 2,400 frames with
presses, into a fight that plays the disc's audio. With the audio bytes left
unswapped the two differ from frame 1750, so the comparison does see them.
The savestate tests pass on the CHD, the one that goes back to a kept state
among them, and a project whose disc is the CHD ends on the same picture in
Chimera's engine.

## Games for the other three systems (2026-10-13)

The owner brought games for the Virtual Boy, the PC-FX and the Lynx. All
three systems ran them at the first try, natively and in the sandbox with
the same digests. What was run, and what the test script now asks of each
(`pcfx:`, `lynx:`, `vb-game:`; the files are named in docs/BUILDING.md):

- **Lynx**: California Games (its title screen) and Chip's Challenge (into
  its story text; A changes the run). 2,400 frames with presses are the same
  natively and in the sandbox, with a state saved and loaded every frame,
  with the state moved to a new sandbox, and after going back to a kept
  state. The boot ROM is needed: without it the console is refused by the
  file's name.
- **Virtual Boy**: Virtual Boy Wario Land (into the first stage), Mario
  Clash and Red Alarm (into play). 3,000 frames of Wario Land with presses
  pass the same comparisons. The default picture is Mednafen's: both eyes in
  one picture, the left in red and the right in blue, so what both eyes see
  is magenta. The setting "How The Two Eyes Are Shown" and the colour
  settings change that.
- **PC-FX**: Last Imperial Prince (Japan). The BIOS starts the disc, the
  game shows its menu and plays its opening film from the disc. 3,000 frames
  with presses pass the same comparisons; the state kept at frame 1,500 and
  loaded at 2,250 is while the film plays from the disc. With the game's
  second disc in the project the selector is live, and the lid closes on the
  disc the selector is on.

**Save data of the PC-FX and of Virtual Boy cartridges** (patch 0008). The
PC-FX wrote its backup memory to a file two seconds after a game changed
it, which in the sandbox was an error message every time; the Virtual Boy
writes a cartridge's memory when a game is closed. Both now stay in memory,
as the Saturn's do, and Export Save Data writes `pcfx.sav` (the console's
backup memory, 32 KB), `pcfx.fxb` (the memory pack, 128 KB) and
`virtualboy.sav` (64 KB). The Save data slot takes `.sav` and `.fxb` files
for these two machines. A changed copy of each PC-FX file given to a project
comes out as it went in. On the Virtual Boy that test uses the test program:
Wario Land wipes a save it does not recognise, which looked like a failure
of the core and was not (the changed bytes are in memory at the first frame
and gone by the thirtieth).

**The Saturn's other memories on the bus** (patch 0009): the sound
processor's RAM (0x05A00000, 512 KB), the VDP1's memory (0x05C00000, 512
KB), the VDP2's memory (0x05E00000, 512 KB), the colour memory (0x05F00000,
4 KB), and a RAM cartridge's (0x02400000 and 0x02600000) when the Cartridge
setting puts one in. Chimera's RAM search now reads 6 ranges and 3,674,112
bytes of the bus with no cartridge. Two things were found on the way:

- Mednafen's drawing code keeps its own copy of the VDP2's memory and of
  the colours. A byte written into the first copy reads back and is never
  seen. So a write to these two goes the way a game's write goes. Measured:
  the three colours of a loading screen's text written through the bus
  turned the text red; with the write made in place instead, the picture
  did not change (the test `saturn:bus-write` fails on that).
- Where a colour is kept depends on the colour mode, so the colour memory
  is read through the function a game's read goes through, not in place.

**The sound is 44.1 kHz**, not 48. The Saturn's sound chip and a CD's audio
run at 44.1 kHz, and Mednafen converted both to the 48 kHz the core asked
for. Asked for 44.1 kHz, Mednafen converts neither. The other three
systems' sound is made at whatever rate is asked, so one rate serves all
four.

**The test runner** can write to the bus (`--poke`), for the test above.

**Windows.** Chimera's headless runner, built for Windows, played a movie
with presses of a game of each system (Wario Land 2,000 frames, Chip's
Challenge 2,000, Last Imperial Prince 2,500, Virtua Fighter Remix 1,500):
the RAM and the last picture are byte for byte those of the Linux runner.
Chimera's window on Windows opened a project of each, the Lynx's, the
PC-FX's and the Saturn's with their firmware from Chimera's Firmware
settings, and ran it; the RAM it left is the Linux runner's at the same
frame. (The window's script stopped at frame 302 where it asked for 300, on
Windows only. That is Chimera's script timing, not this core's, and the
comparison was made at frame 302.)

Counts: the test script 69 passed, 0 failed, 0 skipped with every file and
Chimera's engine; the window test 6 passed; Chimera's package checks 18 of
18. Each new kind of test was broken once and seen to fail: the bus handing
bytes out in the host's order, a bus write made in place, and a save file
not found.

**A CHD of a PC-FX disc**: made from Last Imperial Prince's cue sheet with
chdman 0.264 (24 tracks, the first of them audio and the second the data),
it gives in the sandbox the 60 digests the cue sheet gives natively, over
3,000 frames with presses, into the opening film (`pcfx:chd`).

What is still not done: the ST-V arcade board (no game), and a run on a CI
runner (the repository is not published).
