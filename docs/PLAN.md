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
- Lynx: the boot ROM, no game.
- PC-FX: the BIOS (`pcfx.rom`), no game.
- Virtual Boy: no game. The tests assemble a small program for it
  (`tests/make-vb-program.py`), which is the only thing it has run.

So the Saturn can be proven with games now. The other three need a game
each from the owner before anything can be said of them beyond "it builds".

## Steps

| Step | What | Proof | State |
|---|---|---|---|
| 1 | Native build of the four systems and the frontend; the Saturn boots a game | Picture, sound, a controller press changes the picture | done 2026-10-12: Virtua Fighter Remix, BIOS logo, attract fight, Start changes the picture |
| 2 | The same in the sandbox, with the Saturn's helper thread gone | The reference and the sandbox give the same digests, frame by frame; savestates | done 2026-10-12: 1,500 frames the same natively, in the sandbox, with a state saved and loaded every frame, with the state moved to a new sandbox, and after going back to a kept state |
| 3 | Controllers and settings generated from Mednafen's descriptions; the package | Chimera's package checks; a project run by Chimera's engine | done 2026-10-12: 743 buttons and 232 axes over the four systems, 58 settings; Chimera's package checks pass (18 of 18); a project of Virtua Fighter Remix with its BIOS as firmware plays a movie in Chimera's engine and the movie's presses reach the game |
| 4 | Virtual Boy, PC-FX, Lynx with games | Each boots a game the same natively and in the sandbox | waits for games |
| 5 | Save data, lag frames, disc change, CHD | Tests for each | done 2026-10-12 except CHD: lag frames (all four systems), memory for RAM Watch and RAM Search, the Saturn's save data, the drive's lid and disc selector. Not done: CHD images |
| 6 | Windows, CI (a self-made Virtual Boy program), documents | The test script on a runner | partly, 2026-10-12: the test script (`waterbox/run-gate.sh`, 30 tests) with a Virtual Boy program it assembles itself. Not done: the window test, Windows, the CI workflow, README |
| 7 | Publishing | The owner's word | not started |

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
- **Not done yet**: CHD images, the Saturn's ST-V arcade board.

## What step 5 decided

- **Lag frames**: each system says when its game code is handed a pad's
  state (patch 0006). A frame without that is a lag frame.
- **Memory**: the Virtual Boy's, the PC-FX's and the Lynx's RAM are memory
  domains, from what the systems already tell Mednafen's cheat search. The
  Saturn keeps its RAM as 16-bit words in the host's byte order, so a plain
  view of it would show every pair of bytes swapped: its two work RAMs are
  read through a bus ("System Bus"), at the console's own addresses
  (0x00200000 and 0x06000000) and in the console's byte order. The video
  chips' and the sound chip's memory are not on it yet.
- **Save data** (the Saturn): the backup memory and the backup cartridge
  stay in the machine's memory, and Mednafen's writing of save files is
  turned off (patch 0007). Export Save Data writes `saturn.bkr` and
  `saturn.bcr`, the files Mednafen itself would write, and a project's Save
  data slot takes them back by extension. The PC-FX's and the Virtual Boy
  cartridge's saves are not exported yet: there is no game to test with.
- **The Virtual Boy test program** draws nothing. It counts in RAM and
  copies the pad there, which is enough to compare the sandbox with the
  reference, to test savestates and to test lag frames, on a CI runner.
- **The drive** has three controls, named as Chimera's other disc cores
  name them: Previous Disc and Next Disc move a selector over the project's
  discs, and Disc Swap is the lid, up while held and closing on the selected
  disc (or the next one when the selector was not moved). With the lid up a
  Saturn leaves the game for its own CD screen. The drive's light is lit on
  a frame a sector was read.
