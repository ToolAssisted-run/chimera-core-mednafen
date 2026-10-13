# Building

This core is built on Linux. The result, `core.wbx`, is one file that runs in
Chimera on Linux and on Windows.

## What is needed

- GCC 13 or newer, meson, ninja, curl, patch, git.
- A checkout of Chimera with miniBox built, for the sandbox toolchain
  (Chimera's `AGENTS.md`, "Build"). Below, `<miniBox>` is its
  `extern/chimera-common-minibox` folder.

## Mednafen's source

Mednafen is published as release archives only; it has no public repository.
So the version this core builds is an archive's name and its SHA-256, both
written in `waterbox/fetch-mednafen.sh`:

```sh
git submodule update --init
waterbox/fetch-mednafen.sh
```

downloads the archive once (into `build/cache`), checks it, unpacks it into
`extern/mednafen` and applies the patches in `patches/`. `extern/mednafen`
is not in git. zlib is a submodule because Mednafen brings none and the
sandbox's toolchain has none; libchdr is a submodule for CHD disc images.

A change to Mednafen is kept as a patch. Edit the file in
`extern/mednafen`, build and test, and then:

```sh
waterbox/make-patch.sh NNNN-what-it-does < description.txt
```

writes what differs from the archive with the existing patches as the next
patch, with the description above the diff: what the change is and why.
Every change is inside `#if defined(CHIMERA_CORE)`. `fetch-mednafen.sh`
makes `extern/mednafen` again from the archive whenever a patch changes, so
an edit that was not made into a patch is lost then.

## What is compiled

`waterbox/list-sources.sh` lists Mednafen's files this core compiles: the
four systems (Saturn, Virtual Boy, PC-FX, Lynx), the processors and chips
they share, the disc reader and the general files. Mednafen's own program
(its window, its sound output, its menus, its savestates) is not compiled:
`waterbox/cinterface.cpp` is this core's frontend and
`waterbox/mdfn-interfaces.cpp` answers what Mednafen's files ask of the
program. `waterbox/config/config.h` is written by hand in place of the one
Mednafen's configure script would make.

## The two flavors

- `native`: for the host. `run-native` is the reference the tests compare
  the sandbox with.
- `guest`: for miniBox's sandbox. This is `core.wbx`, and `run-wbx` runs it.

```sh
meson setup build/meson-native -Dminibox_dir=<miniBox> && ninja -C build/meson-native
waterbox/setup-guest.sh -m <miniBox> && ninja -C build/meson-guest
```

## Running a game by hand

Put each game in a folder of its own under `tests/games-local` and the BIOS
files in `tests/roms-local`. Both folders are ignored by git; nothing in them
is ever committed.

```sh
tests/try.sh saturn <folder> --frames 1800 --report 300 --list-panel
tests/try.sh -g saturn <folder> --frames 1800 --report 300     # in the sandbox
tests/try.sh -g saturn <folder> --frames 1500 --report 50 --rewind
```

The two first print the same lines when the sandbox runs the game as the
reference does. The run options are in `waterbox/gate-harness.h`. `run-wbx`
has three more, each of which must leave the printed lines unchanged:
`--rerecord` (a state saved and loaded every frame), `--session` (the state
moved to a new sandbox half way) and `--rewind` (a state kept half way and
loaded again at three quarters; the frames after the load repeat those after
the save).

## The controls and the settings

The package's controls and settings are generated, not written:

```sh
build/meson-native/run-native --describe > /tmp/describe.json
waterbox/gen-config.py /tmp/describe.json
```

`--describe` prints Mednafen's own tables for the four systems: every port,
every device a port takes, every input of each device, every setting.
`waterbox/machines.json` holds what is written by hand: the names Chimera
shows, which port is which player, and the settings a project may set with
their descriptions. `gen-config.py` writes `waterbox/panel.inc` (compiled
into the core), `waterbox/waterbox.config` and
`waterbox/default_keybinds.json`, and stops when `machines.json` names
something Mednafen does not have. Run it again, and rebuild, after changing
`machines.json` or the Mednafen version.

## The package

```sh
waterbox/build-package.sh -r <chimera checkout>
```

builds the sandbox core and writes `build/Cores/mednafen.chimeraCore` in
that checkout. `tests/make-project.py` writes a project for a game, which
Chimera's `chimera-run --project` then plays.

## The tests

```sh
CHIMERA_ROOT=<chimera checkout> waterbox/run-gate.sh
```

runs every test and says, for each, what was compared. The "vb:" tests need
nothing: the script assembles a small Virtual Boy program. The others need
files that cannot be in this repository, and say SKIP without them:

| Tests | What they need | Where the script looks | Or name it with |
|---|---|---|---|
| `saturn:` | a game, as a folder with a `.cue` and its tracks | `tests/games-local/vfremix` | `SATURN_GAME` |
| | the two BIOS files | `tests/roms-local/sega_101.bin`, `mpr-17933.bin` | `SATURN_BIOS_JP`, `SATURN_BIOS_NA_EU` |
| `saturn:disc-change` | any second Saturn disc | `tests/games-local/vf2` | `SATURN_GAME2` |
| `saturn:chd...` | a `.chd` of the first game (`chdman createcd -i <the .cue> -o <a .chd>`) | `tests/games-local/vfremix-chd` | `SATURN_GAME_CHD` |
| `pcfx:` | a game, as a folder with a `.cue` and its tracks, and the BIOS | `tests/games-local/pcfx`, `tests/roms-local/pcfx.rom` | `PCFX_GAME`, `PCFX_BIOS` |
| `pcfx:disc-change` | any second PC-FX disc | `tests/games-local/pcfx2` | `PCFX_GAME2` |
| `pcfx:chd` | a `.chd` of the first PC-FX game | `tests/games-local/pcfx-chd` | `PCFX_GAME_CHD` |
| `lynx:` | a game, as a folder with a `.lnx` file, and the boot ROM | `tests/games-local/lynx`, `tests/roms-local/lynxboot.img` | `LYNX_GAME`, `LYNX_BOOT` |
| `vb-game:` | a game, as a folder with a `.vb` file | `tests/games-local/vb` | `VB_GAME` |

Copy the files there; do not link them from where you keep them. Without
`CHIMERA_ROOT` the tests that run the package in Chimera's engine are
skipped.

`bash tests/run-frontend.sh --chimera-root <chimera checkout>` is the window
test: the package in Chimera's own window (under Mono, on a private Xvfb
display). It takes the same files.
