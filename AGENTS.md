# AGENTS.md - Mednafen core for Chimera

This repository builds four systems of Mednafen (https://mednafen.github.io/)
- the Sega Saturn, the Virtual Boy, the PC-FX and the Atari Lynx - as a core
for Chimera (https://github.com/ToolAssisted-run/chimera), a frontend for
tool-assisted speedruns. It produces one file, `mednafen.chimeraCore`:
Mednafen's emulation compiled to run inside Chimera's sandbox (miniBox), one
frontend over Mednafen's own description of a system, and the declarations
Chimera reads (buttons, settings, file types, firmware). Mednafen's own
program - its window, sound output, menus and savestates - is not built.

Read [docs/BUILDING.md](docs/BUILDING.md) before building and
[docs/PLAN.md](docs/PLAN.md) before changing how the core works: it is the
design log, with what was decided, why, and what was measured.

## Layout

- `extern/mednafen` - Mednafen 1.32.1, NOT in git: `waterbox/fetch-mednafen.sh`
  downloads the official archive, checks its SHA-256, unpacks it and applies
  `patches/`. Mednafen has no public repository, so the version is the
  archive. `extern/zlib` - zlib, and `extern/libchdr` - libchdr 0.3.0, for
  CHD disc images: both submodules.
- `patches/` - the numbered patches, each with what it changes and why above
  the diff. Every change is inside `#if defined(CHIMERA_CORE)`.
- `meson.build` - the build of both flavors. `waterbox/list-sources.sh`
  lists Mednafen's files that are compiled. `waterbox/config/` - `config.h`,
  written by hand in place of the one Mednafen's configure would make.
- `waterbox/cinterface.cpp` - the frontend: the functions Chimera's engine
  calls, over Mednafen's description of a system (`MDFNGI`). The same file is
  compiled for the sandbox and for the host.
- `waterbox/chd-disc.cpp` - CHD disc images: a CHD shown to Mednafen's own
  cue reader as the cue sheet and track files it stands for.
- `waterbox/mdfn-interfaces.cpp` - what Mednafen's files ask of its program
  (settings, file names, messages), answered. `waterbox/frontend.h` is what
  it asks of `cinterface.cpp`.
- `waterbox/machines.json` - written by hand: Chimera's names for the
  systems, which port is which player, control names where Mednafen's would
  collide, and the settings a project may set, with their descriptions.
- `waterbox/gen-config.py` - writes `panel.inc` (the controls, compiled into
  the core), `waterbox.config` and `default_keybinds.json` from Mednafen's
  own tables (`run-native --describe`) and `machines.json`. Those three
  files are generated: do not edit them.
- `waterbox/file_slots.json`, `package-licenses.json` - the rest of what the
  package declares.
- `waterbox/run-native.c`, `waterbox/run-wbx.c` - the native runner and the
  sandbox runner. They take the same options and print the same lines
  (`waterbox/gate-harness.h` is the part they share).
- `waterbox/*.sh` - `fetch-mednafen.sh`, `make-patch.sh`, `setup-guest.sh`
  (configures the sandbox build), `build-package.sh`, `run-gate.sh` (the
  test script).
- `tests/` - `run-frontend.sh` (the window test, with its helpers),
  `make-vb-program.py` (assembles the Virtual Boy program the tests run),
  `make-project.py` (writes a project for a game), `try.sh` (runs a game by
  hand).
- `build/` - every build output. `tests/roms-local/` - BIOS files, and
  `tests/games-local/` - games, for the tests that need them. All three are
  ignored by git.

## Build and test

```sh
git submodule update --init
waterbox/fetch-mednafen.sh
meson setup build/meson-native -Dminibox_dir=<chimera>/extern/chimera-common-minibox
ninja -C build/meson-native
waterbox/build-package.sh -r <chimera>
CHIMERA_ROOT=<chimera> waterbox/run-gate.sh
bash tests/run-frontend.sh --chimera-root <chimera>
```

The test script must end with `0 failed`. Run it before every commit that
changes the core, and say in the commit what it printed.

The "vb:" tests need no file: the script assembles a small Virtual Boy
program. Every other system's tests need a game, and all but the Virtual
Boy's the console's BIOS or boot ROM, which this repository cannot contain.
The script looks for them under `tests/games-local` and `tests/roms-local`
(the folder and file names are at the top of `waterbox/run-gate.sh`, with
the environment variables that point elsewhere: `SATURN_GAME`,
`SATURN_GAME2`, `SATURN_GAME_CHD`, `SATURN_BIOS_JP`, `SATURN_BIOS_NA_EU`,
`PCFX_GAME`, `PCFX_GAME2`, `PCFX_BIOS`, `LYNX_GAME`, `LYNX_BOOT`,
`VB_GAME`). Without them the script says SKIP. A skipped test proves
nothing: if you do not have the files, say so in your report.

## Rules

- **Never edit `patches/` by hand.** Edit the tree under `extern/mednafen`,
  build, test, and run `waterbox/make-patch.sh <NNNN-what-it-does> <
  description.txt`. An edit that is not made into a patch is lost the next
  time `fetch-mednafen.sh` remakes the tree.
- **Patch as little as possible.** What can be done in `cinterface.cpp` or
  `mdfn-interfaces.cpp` is done there. A patch is for what only Mednafen's
  own file can do: its private memory, a place in its code where a game
  reads a pad.
- **Nothing about a controller or a setting is typed twice.** Devices,
  inputs, a setting's type, default, limits and choices come from Mednafen's
  tables. `machines.json` holds names and descriptions only, and
  `gen-config.py` stops when it names something Mednafen does not have.
  After changing it: `run-native --describe`, `gen-config.py`, rebuild.
- **One thread.** A core runs on one thread on one clock. Mednafen's helper
  threads are patched out (0001, 0002); do not add one.
- **The machine's state is its memory.** A savestate is the sandbox's copy
  of the core's memory, so nothing a game can change may live in a file or
  in memory marked invisible. Save data stays in memory (patches 0007 and
  0008). An
  open file's position is NOT in a savestate: seek before every read (patch
  0004), and test with `run-wbx --rewind`, which is the test that finds it.
- **Files are found by plain name.** The sandbox has no folders: `name`, not
  `./name` (patch 0003).
- **No BIOS, no game, no key** is committed, uploaded to CI or attached to
  an issue. Test content stays under `tests/roms-local` and
  `tests/games-local`, and is copied there, never linked from where the
  owner keeps it.
- **Say what was not tried.** A system that built and never ran a game has
  not been shown to work.
- **Write in plain language**: commit messages, documents, comments and
  setting descriptions are read by people who have never seen this
  repository. `.md` files are ASCII.
- **Commits**: `type(scope): what changed`; a short body with what changed,
  why, and how it was tested, with the numbers. Stage explicit paths. No
  amending, no force push.

## What is the owner's to decide

Publishing, the roster row in Chimera, a new Mednafen version, and anything
a licence does not plainly allow.
