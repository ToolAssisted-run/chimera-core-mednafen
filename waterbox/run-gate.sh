#!/bin/sh
# The core's tests. Each line says what was compared. The script ends with a
# count of tests that passed, failed and were skipped, and with an error if
# any failed. A skipped test is not a pass.
#
#   waterbox/run-gate.sh
#
# CHIMERA_ROOT=<a Chimera checkout> adds the tests that run the package in
# Chimera's own headless runner (waterbox/build-package.sh -r <it> first).
# SATURN_GAME=<folder> is a Saturn game for the tests that need one: a
# folder holding a .cue and its track files (tests/games-local/vfremix when
# not given). SATURN_GAME2=<folder> is any second Saturn disc, for the test
# that changes discs (tests/games-local/vf2 when not given). SATURN_GAME_CHD
# is a .chd file made from SATURN_GAME's cue sheet (chdman createcd), for the
# test that a CHD reads as its cue sheet does (the .chd in
# tests/games-local/vfremix-chd when not given). SATURN_BIOS_JP and
# SATURN_BIOS_NA_EU are the two BIOS files (tests/roms-local/sega_101.bin and
# mpr-17933.bin when not given).
# PCFX_GAME=<folder> is a PC-FX game, a .cue and its track files
# (tests/games-local/pcfx), PCFX_GAME2 any second PC-FX disc
# (tests/games-local/pcfx2), PCFX_GAME_CHD a .chd made from PCFX_GAME's cue
# sheet (the .chd in tests/games-local/pcfx-chd) and PCFX_BIOS the console's
# BIOS (tests/roms-local/pcfx.rom). LYNX_GAME=<folder> holds a Lynx game, a .lnx
# file (tests/games-local/lynx), and LYNX_BOOT is the Lynx's boot ROM
# (tests/roms-local/lynxboot.img). VB_GAME=<folder> holds a Virtual Boy game,
# a .vb file (tests/games-local/vb). STV_GAME=<folder> holds a game of the
# ST-V arcade board, a .zip of its ROM files as MAME names them
# (tests/games-local/stv), and STV_BIOS is MAME's set of the board's BIOS
# files (tests/roms-local/stvbios.zip). STV_GAME_UPRIGHT=<folder> holds an
# ST-V game whose monitor stands on its side (tests/games-local/stv-shienryu)
# and STV_GAME_HAMMER=<folder> one that is played with a hammer
# (tests/games-local/stv-hammer).
#
# Needs the native build (meson setup build/meson-native ... && ninja) and
# the sandboxed core (waterbox/setup-guest.sh && ninja -C build/meson-guest):
# docs/BUILDING.md.
#
# WHAT RUNS WITH NO FILES OF YOURS. No BIOS and no game may be put in this
# repository or on a CI runner. The Virtual Boy needs no BIOS, and
# tests/make-vb-program.py assembles a small program for it, so the "vb:"
# tests run everywhere: the processor runs, the pad reaches the program,
# its reads of the pad are seen, a save file goes in and comes out, and the
# sandbox gives the native build's results with savestates. The Saturn, PC-FX,
# Lynx and ST-V tests need a game and the machine's BIOS or boot ROM, and the
# "vb-game:" tests a Virtual Boy game; each says SKIP without its files.
#
# The ways a test passes on a broken thing (Chimera's docs/gates.md) that
# these are written against: a machine that did nothing agrees with itself,
# so a run is first checked to have got somewhere; the end of a run hides a
# run that went another way and came back, so runs are compared as a stream
# of digests; and a comparison that cannot fail proves nothing, so each
# "the same" has a run beside it that must come out different.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
native="$root/build/meson-native/run-native"
runwbx="$root/build/meson-native/run-wbx"
core="$root/build/meson-guest/core.wbx"
chimera_root="${CHIMERA_ROOT:-}"
game="${SATURN_GAME:-$root/tests/games-local/vfremix}"
game2="${SATURN_GAME2:-$root/tests/games-local/vf2}"
game_chd="${SATURN_GAME_CHD:-$(ls "$root"/tests/games-local/vfremix-chd/*.chd 2> /dev/null | head -1)}"
bios_jp="${SATURN_BIOS_JP:-$root/tests/roms-local/sega_101.bin}"
bios_na="${SATURN_BIOS_NA_EU:-$root/tests/roms-local/mpr-17933.bin}"
fxgame="${PCFX_GAME:-$root/tests/games-local/pcfx}"
fxgame2="${PCFX_GAME2:-$root/tests/games-local/pcfx2}"
fxgame_chd="${PCFX_GAME_CHD:-$(ls "$root"/tests/games-local/pcfx-chd/*.chd 2> /dev/null | head -1)}"
fxbios="${PCFX_BIOS:-$root/tests/roms-local/pcfx.rom}"
lxgame="${LYNX_GAME:-$root/tests/games-local/lynx}"
lxboot="${LYNX_BOOT:-$root/tests/roms-local/lynxboot.img}"
svgame="${STV_GAME:-$root/tests/games-local/stv}"
svgame_up="${STV_GAME_UPRIGHT:-$root/tests/games-local/stv-shienryu}"
svgame_hammer="${STV_GAME_HAMMER:-$root/tests/games-local/stv-hammer}"
svbios="${STV_BIOS:-$root/tests/roms-local/stvbios.zip}"
vbgame="${VB_GAME:-$root/tests/games-local/vb}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ok=0; failed=0; skipped=0
report() { # <test> <PASS|FAIL|SKIP> <what>
	printf '%-22s %-6s %s\n' "$1" "$2" "$3"
	case "$2" in PASS) ok=$((ok + 1)) ;; FAIL) failed=$((failed + 1)) ;; *) skipped=$((skipped + 1)) ;; esac
}
# check <test> <what> <condition...>
check() {
	ck_test="$1"; ck_what="$2"; shift 2
	if "$@"; then report "$ck_test" PASS "$ck_what"; else report "$ck_test" FAIL "$ck_what"; fi
}
stream() { grep '^frame' "$1"; }
same() { [ -s "$1" ] && [ -s "$2" ] && cmp -s "$1" "$2"; }
differ() { [ -s "$1" ] && [ -s "$2" ] && ! cmp -s "$1" "$2"; }
# field <file> <name>: the value after a name in the file's last report line
field() { stream "$1" | tail -1 | awk -v f="$2" '{for (i = 1; i <= NF; i++) if ($i == f) { print $(i + 1); exit }}'; }
# folder <name> <settings json> <slot> <game file> [<save data file>...]: a
# work folder as the sandbox mounts a project - every file under its name,
# the firmware under the names the package gives it
folder() {
	fd_dir="$work/$1"; fd_settings="$2"; fd_slot="$3"; fd_game="$4"; shift 4
	mkdir -p "$fd_dir"
	for fd_f in "$(dirname "$fd_game")"/*; do [ -f "$fd_f" ] && ln -sf "$fd_f" "$fd_dir/$(basename "$fd_f")"; done
	fd_saves=""
	for fd_f in "$@"; do
		cp "$fd_f" "$fd_dir/"
		fd_saves="$fd_saves${fd_saves:+,}\"$(basename "$fd_f")\""
	done
	printf '{"%s":["%s"],"savedata":[%s]}' "$fd_slot" "$(basename "$fd_game")" "$fd_saves" > "$fd_dir/slots"
	printf '%s' "$fd_settings" > "$fd_dir/settings"
}
nat() { nt_out="$1"; nt_dir="$2"; shift 2; "$native" "$work/$nt_dir" "$@" > "$work/$nt_out.out" 2> "$work/$nt_out.err"; }
box() { bx_out="$1"; bx_dir="$2"; shift 2; "$runwbx" "$core" "$work/$bx_dir" "$@" > "$work/$bx_out.out" 2> "$work/$bx_out.err"; }
# repeats <file> <first> <second> <count> <step>: do the report lines from
# frame <second> on repeat those from frame <first> on (run-wbx --rewind).
# The count of lag frames is the runner's own and goes on counting, so it is
# left out.
repeats() {
	awk -v a="$2" -v b="$3" -v n="$4" -v step="$5" '
		/^frame/ { f = $2; $1 = ""; $2 = ""; sub(/ lag [0-9]+$/, ""); line[f] = $0 }
		END {
			for (i = step; i < n; i += step) {
				if (!((a + i) in line) || !((b + i) in line) || line[a + i] != line[b + i]) exit 1
				seen++
			}
			exit seen > 0 ? 0 : 1
		}' "$1"
}
# save_round_trip <test> <machine> <slot> <game file> <exported folder> <ext> <label> <what> [<frames>]:
# a save file that came out, changed in the middle and given to a project,
# comes out of that project as it went in. <label> is text the file's first
# 16 bytes hold (the memory's own format label), or nothing. The project runs
# 300 frames, or <frames>: an arcade board's BIOS checks its memories as it
# starts and mends what it finds changed, so those are read back at once.
save_round_trip() {
	rt_test="$1"; rt_machine="$2"; rt_slot="$3"; rt_game="$4"; rt_from="$5"; rt_ext="$6"; rt_magic="$7"; rt_what="$8"; rt_frames="${9:-300}"
	rt_file="$rt_from/$rt_machine.$rt_ext"
	if [ ! -s "$rt_file" ]; then report "$rt_test" FAIL "no $rt_what was exported"; return; fi
	mkdir -p "$work/$rt_test-mine" "$work/$rt_test-out"
	python3 - "$rt_file" "$work/$rt_test-mine/mine.$rt_ext" <<'PY'
import sys
b = bytearray(open(sys.argv[1], "rb").read())
at = len(b) // 2
b[at:at + 4] = b"\xa5\x5a\xc3\x3c"
open(sys.argv[2], "wb").write(b)
PY
	folder "$rt_test" "{\"machine\":\"$rt_machine\"}" "$rt_slot" "$rt_game" "$work/$rt_test-mine/mine.$rt_ext"
	[ "$rt_machine" = pcfx ] && ln -sf "$fxbios" "$work/$rt_test/pcfx.rom"
	[ "$rt_machine" = stv ] && ln -sf "$svbios" "$work/$rt_test/stvbios.zip"
	box "$rt_test" "$rt_test" --frames "$rt_frames" --report "$rt_frames" --savedata-out "$work/$rt_test-out"
	check "$rt_test" "$rt_what goes out as a file of $(wc -c < "$rt_file") bytes; a changed copy given to a project comes out as it went in" \
		sh -c "head -c 16 '$rt_file' | grep -q -a '$rt_magic' && cmp -s '$work/$rt_test-mine/mine.$rt_ext' '$work/$rt_test-out/$rt_machine.$rt_ext' && ! cmp -s '$rt_file' '$work/$rt_test-out/$rt_machine.$rt_ext'"
}

if [ ! -x "$native" ] || [ ! -x "$runwbx" ] || [ ! -f "$core" ]; then
	echo "not built: this needs build/meson-native/run-native and run-wbx, and build/meson-guest/core.wbx (docs/BUILDING.md)" >&2
	exit 1
fi

# ------------------------------------------------- the source and the package
# Mednafen's source is the pinned archive with exactly the patches of patches/
want="$(cat "$root"/patches/*.patch | sha256sum | cut -d' ' -f1)"
check "source:patched" "extern/mednafen is the pinned archive with the $(ls "$root"/patches/*.patch | wc -l) patches of patches/" \
	grep -q " $want\$" "$root/extern/mednafen/.chimera-version"

# the package's declarations are what Mednafen's own tables and machines.json give
mkdir -p "$work/gen"
"$native" --describe > "$work/describe.json" 2> "$work/describe.err"
python3 "$here/gen-config.py" "$work/describe.json" "$work/gen" > "$work/gen.log" 2>&1
gen_ok=1
for f in panel.inc waterbox.config default_keybinds.json; do
	cmp -s "$work/gen/$f" "$here/$f" || gen_ok=0
done
check "package:generated" "panel.inc, waterbox.config and default_keybinds.json are what gen-config.py writes ($(tail -1 "$work/gen.log"))" [ "$gen_ok" = 1 ]

# a sandbox build that failed must not be tested as the previous one
stale=""
for src in "$here"/cinterface.cpp "$here"/mdfn-interfaces.cpp "$here"/panel.inc "$root"/patches/*.patch; do
	[ "$core" -nt "$src" ] || stale="$stale $(basename "$src")"
done
check "package:fresh" "core.wbx is not older than its sources${stale:+ (older than:$stale)}" [ -z "$stale" ]

# ------------------------------------------------- the Virtual Boy, everywhere
mkdir -p "$work/vbgame" "$work/vbquiet"
python3 "$root/tests/make-vb-program.py" "$work/vbgame/chimera-test.vb"
python3 "$root/tests/make-vb-program.py" "$work/vbquiet/chimera-test.vb" --no-pad
folder vb '{"machine":"virtualboy"}' cart "$work/vbgame/chimera-test.vb"
folder vbq '{"machine":"virtualboy"}' cart "$work/vbquiet/chimera-test.vb"
vbrun="--frames 300 --report 10 --press 0:100:40 --press 9:150:40 --press 10:200:20"

nat vb-idle vb --frames 300 --report 10
nat vb vb $vbrun --list-panel --dump-domain WRAM "$work/vb.wram"
box vb-box vb $vbrun
stream "$work/vb.out" > "$work/vb.stream"
stream "$work/vb-idle.out" > "$work/vb-idle.stream"
stream "$work/vb-box.out" > "$work/vb-box.stream"

# the program counts in RAM: a processor that does not run leaves it at 0
count="$(od -An -tu4 -N4 "$work/vb.wram" 2> /dev/null | tr -d ' ')"
check "vb:runs" "a program this script assembles runs: its counter in RAM reached ${count:-nothing} in 300 frames" [ "${count:-0}" -gt 1000 ]
check "vb:pad" "A, Up and Start change what the program copies of the pad into RAM (the idle run's RAM differs)" \
	differ "$work/vb.stream" "$work/vb-idle.stream"
check "vb:sandbox" "native and sandbox print the same $(wc -l < "$work/vb.stream") digests of RAM, picture and sound, with presses" \
	same "$work/vb.stream" "$work/vb-box.stream"
check "vb:controls" "the panel lists the pad's 14 buttons and the battery switch as live" \
	[ "$(grep -c "^panel .* active\$" "$work/vb.out")" = 15 ]

# lag: the program reads the pad every frame; its twin never does
nat vbq vbq --frames 100 --report 100
check "vb:lag" "no lag frame in 300 of a program that reads the pad ($(field "$work/vb.out" lag)), 100 of 100 in one that never does ($(field "$work/vbq.out" lag))" \
	[ "$(field "$work/vb.out" lag)" = 0 -a "$(field "$work/vbq.out" lag)" = 100 ]

box vb-rerecord vb $vbrun --rerecord
box vb-session vb $vbrun --session
box vb-rewind vb --frames 300 --report 5 --rewind
stream "$work/vb-rerecord.out" > "$work/vb-rerecord.stream"
stream "$work/vb-session.out" > "$work/vb-session.stream"
check "vb:state-every-frame" "a state saved and loaded every frame changes nothing" same "$work/vb-box.stream" "$work/vb-rerecord.stream"
check "vb:state-other-box" "a state moved to a new sandbox half way changes nothing" same "$work/vb-box.stream" "$work/vb-session.stream"
check "vb:state-rewind" "a state kept at frame 150 and loaded at 225: the frames after the load repeat those after the save" \
	repeats "$work/vb-rewind.out" 150 225 75 5
# a cartridge's save memory: the program leaves it alone, so what goes in
# must come out
mkdir -p "$work/vb-saves"
nat vb-save vb --frames 10 --report 10 --savedata-out "$work/vb-saves"
save_round_trip "vb:save-data" virtualboy cart "$work/vbgame/chimera-test.vb" "$work/vb-saves" sav '' "a cartridge's save memory"

# ------------------------------------------------- what is refused
mkdir -p "$work/none"
printf '{}' > "$work/none/slots"
printf '{"machine":"saturn"}' > "$work/none/settings"
nat none none --frames 1
check "refused:no-game" "a Saturn with no disc is refused, and says so" grep -q "error.no_disc" "$work/none.out" "$work/none.err"
printf '{"machine":"dreamcast"}' > "$work/none/settings"
nat nomachine none --frames 1
check "refused:machine" "a machine this core does not have is refused by name" grep -q 'error.bad_machine[^a-z]dreamcast' "$work/nomachine.out" "$work/nomachine.err"

# ------------------------------------------------- the Saturn, with a game
cue="$(ls "$game"/*.cue 2> /dev/null | head -1)"
if [ -n "$cue" ] && [ -f "$bios_jp" ] && [ -f "$bios_na" ]; then
	sat_firmware() { ln -sf "$bios_jp" "$work/$1/saturn_jp.bin"; ln -sf "$bios_na" "$work/$1/saturn_na_eu.bin"; }
	folder ss '{"machine":"saturn"}' disc "$cue"; sat_firmware ss
	# Start twice, a minute apart on the console's clock: past the title
	# screen of most games
	ssrun="--frames 1500 --report 50 --press 11:900:10 --press 11:1300:10"
	mkdir -p "$work/ss-saves" "$work/ss-saves2"
	nat ss-idle ss --frames 1500 --report 50
	nat ss ss $ssrun --list-panel --savedata-out "$work/ss-saves" --dump-domain bus:0x06002000:16 "$work/ss.header"
	box ss-box ss $ssrun
	for n in ss ss-idle ss-box; do stream "$work/$n.out" > "$work/$n.stream"; done

	pictures="$(awk '{print $7}' "$work/ss.stream" | sort -u | wc -l)"
	check "saturn:runs" "the game runs: $pictures different pictures in 30 reports, and sound" [ "$pictures" -gt 5 ]
	check "saturn:pad" "Start pressed twice changes the run (the idle run's digests differ)" differ "$work/ss.stream" "$work/ss-idle.stream"
	check "saturn:sandbox" "native and sandbox print the same $(wc -l < "$work/ss.stream") digests of RAM, picture and sound, with presses" \
		same "$work/ss.stream" "$work/ss-box.stream"
	check "saturn:controls" "port 1's pad of 13 buttons, Reset and the drive's lid are live and nothing of port 2, which starts empty, of the 594 buttons the Saturn declares" \
		sh -c "[ \"\$(grep -c '^panel .* active\$' '$work/ss.out')\" = 15 ] && grep -q \"'P1 A' active\" '$work/ss.out' && ! grep -q \"'P2 A' active\" '$work/ss.out'"
	# the BIOS copies the disc's header to 0x06002000; the Saturn keeps its RAM
	# as words, so this also says the bus hands bytes out in the console's order
	check "saturn:bus" "the bus reads \"$(tr -d '\0' < "$work/ss.header" 2> /dev/null)\" at 0x06002000, where the BIOS puts the disc's header" \
		[ "$(cat "$work/ss.header" 2> /dev/null)" = "SEGA SEGASATURN " ]
	# the other memories on the bus: the sound processor's RAM begins with the
	# table its program starts from, and the colours are in use
	nat ss-mem ss $ssrun --dump-domain bus:0x05A00000:8 "$work/ss.sound"
	nat ss-mem2 ss $ssrun --dump-domain bus:0x05F00000:4096 "$work/ss.colours"
	# a 68000 starts from two numbers at the bottom of its memory, a stack
	# address and a start address past the table they head; bytes handed out in
	# the wrong order do not make such a pair
	check "saturn:bus-memories" "the bus also reads the sound processor's RAM (it begins $(od -An -tx1 "$work/ss.sound" 2> /dev/null | tr -d ' \n'): the stack and start addresses of its program) and the colour memory ($(tr -d '\0' < "$work/ss.colours" 2> /dev/null | wc -c) of 4096 bytes in use)" \
		python3 -c "
import sys
b = open(sys.argv[1], 'rb').read()
stack, start = int.from_bytes(b[0:4], 'big'), int.from_bytes(b[4:8], 'big')
colours = sum(1 for x in open(sys.argv[2], 'rb').read() if x)
sys.exit(0 if 0x400 <= stack <= 0x80000 and 0x400 <= start < 0x80000 and start % 2 == 0 and colours > 16 else 1)" "$work/ss.sound" "$work/ss.colours"
	# a write to the colour memory is seen: every colour made the same one
	# leaves a picture of one colour, the same natively and in the sandbox
	nat ss-poke ss $ssrun --poke 0x05F00000:4096:0x1F:1490:11
	box ss-poke-box ss $ssrun --poke 0x05F00000:4096:0x1F:1490:11
	last() { stream "$1" | tail -1 | awk -v n="$2" '{print $n}'; }   # 7 is the picture's digest, 10 the sound's
	check "saturn:bus-write" "every byte of the colour memory written through the bus for the last 11 frames changes the last picture ($(last "$work/ss-poke.out" 7) against $(last "$work/ss.out" 7)) and not the sound, the same in the sandbox" \
		[ -n "$(last "$work/ss-poke.out" 7)" -a "$(last "$work/ss-poke.out" 7)" != "$(last "$work/ss.out" 7)" -a "$(last "$work/ss-poke.out" 10)" = "$(last "$work/ss.out" 10)" -a "$(last "$work/ss-poke.out" 7)" = "$(last "$work/ss-poke-box.out" 7)" -a "$(last "$work/ss-poke.out" 4)" = "$(last "$work/ss-poke-box.out" 4)" ]
	lag="$(field "$work/ss.out" lag)"
	check "saturn:lag" "lag frames are counted while the BIOS starts and the game loads ($lag of 1500), and not on every frame" \
		[ "${lag:-0}" -gt 0 -a "${lag:-0}" -lt 1500 ]

	box ss-rerecord ss $ssrun --rerecord
	box ss-session ss $ssrun --session
	box ss-rewind ss --frames 1500 --report 5 --rewind
	stream "$work/ss-rerecord.out" > "$work/ss-rerecord.stream"
	stream "$work/ss-session.out" > "$work/ss-session.stream"
	check "saturn:state-every-frame" "a state saved and loaded every frame changes nothing" same "$work/ss-box.stream" "$work/ss-rerecord.stream"
	check "saturn:state-other-box" "a state moved to a new sandbox half way changes nothing" same "$work/ss-box.stream" "$work/ss-session.stream"
	# the test that found the disc reads going wrong after a load (patch 0004)
	check "saturn:state-rewind" "a state kept at frame 750 and loaded at 1125, while the game reads its disc: the frames after the load repeat those after the save" \
		repeats "$work/ss-rewind.out" 750 1125 375 5

	# settings reach Mednafen: the side borders off make the picture narrower
	folder ss-narrow '{"machine":"saturn","ss.h_overscan":false}' disc "$cue"; sat_firmware ss-narrow
	nat ss-narrow ss-narrow --frames 300 --report 300
	check "saturn:setting" "the side borders turned off narrow the picture ($(field "$work/ss-narrow.out" vid) against $(stream "$work/ss.out" | sed -n 6p | awk '{print $6}'))" \
		[ "$(field "$work/ss-narrow.out" vid)" != "$(stream "$work/ss.out" | sed -n 6p | awk '{print $6}')" ]

	# what is plugged in decides which controls are live
	folder ss-ports '{"machine":"saturn","ss.input.port1":"3dpad","ss.input.port2":"mouse","ss.input.port6":"gamepad","ss.input.port7":"gamepad","ss.input.port8":"gamepad","ss.input.sport2.multitap":true}' disc "$cue"; sat_firmware ss-ports
	nat ss-ports ss-ports --frames 1 --list-panel
	check "saturn:devices" "a 3D pad in port 1, a mouse in port 2, a multitap in socket 2 and pads in ports 6, 7 and 8: the 3D pad's mode switch and the mouse's buttons are live, port 7 is the last one the multitap reaches, and port 5, where nothing was put, is empty" \
		sh -c "grep -q \"'P1 Mode Analog' active\" '$work/ss-ports.out' && grep -q \"'P2 Mouse Left' active\" '$work/ss-ports.out' && grep -q \"'P6 A' active\" '$work/ss-ports.out' && grep -q \"'P7 A' active\" '$work/ss-ports.out' && ! grep -q \"'P8 A' active\" '$work/ss-ports.out' && ! grep -q \"'P5 A' active\" '$work/ss-ports.out' && ! grep -q \"'P2 A' active\" '$work/ss-ports.out'"

	# the drive: the lid up for two seconds takes the game away, and the
	# console goes to its own screen
	index_of() { awk -v n="'$2'" 'index($0, n) && $1 == "panel" { print $2; exit }' "$1"; }
	swap="$(index_of "$work/ss.out" "Disc Swap")"
	nat ss-lid ss $ssrun --press "$swap:1350:120"
	box ss-lid-box ss $ssrun --press "$swap:1350:120"
	stream "$work/ss-lid.out" > "$work/ss-lid.stream"
	stream "$work/ss-lid-box.out" > "$work/ss-lid-box.stream"
	check "saturn:lid" "Disc Swap held for 120 frames changes the run from there on, the same natively and in the sandbox" \
		sh -c "! cmp -s '$work/ss.stream' '$work/ss-lid.stream' && [ \"\$(head -26 '$work/ss.stream')\" = \"\$(head -26 '$work/ss-lid.stream')\" ] && cmp -s '$work/ss-lid.stream' '$work/ss-lid-box.stream'"
	cue2="$(ls "$game2"/*.cue 2> /dev/null | head -1)"
	if [ -n "$cue2" ]; then
		# two discs: the lid alone closes on the next disc; the selector moved
		# twice (there and back) closes it on the first again
		folder ss2 '{"machine":"saturn"}' disc "$cue"; sat_firmware ss2
		for f in "$game2"/*; do ln -sf "$f" "$work/ss2/$(basename "$f")"; done
		printf '{"disc":["%s","%s"],"savedata":[]}' "$(basename "$cue")" "$(basename "$cue2")" > "$work/ss2/slots"
		nat ss2-list ss2 --frames 1 --list-panel
		next="$(index_of "$work/ss2-list.out" "Next Disc")"; swap2="$(index_of "$work/ss2-list.out" "Disc Swap")"
		nat ss2-next ss2 --frames 2100 --report 100 --press "$swap2:1350:120"
		nat ss2-same ss2 --frames 2100 --report 100 --press "$swap2:1350:120" --press "$next:1360:5" --press "$next:1380:5"
		box ss2-box ss2 --frames 2100 --report 100 --press "$swap2:1350:120"
		for n in ss2-next ss2-same ss2-box; do stream "$work/$n.out" > "$work/$n.stream"; done
		check "saturn:disc-change" "with two discs the selector is live; the lid alone closes on the second disc and the selector moved there and back closes it on the first (the two runs end differently), the same in the sandbox" \
			sh -c "grep -q \"'Next Disc' active\" '$work/ss2-list.out' && ! grep -q \"'Next Disc' active\" '$work/ss.out' && [ \"\$(tail -1 '$work/ss2-next.stream')\" != \"\$(tail -1 '$work/ss2-same.stream')\" ] && cmp -s '$work/ss2-next.stream' '$work/ss2-box.stream' && [ -s '$work/ss2-next.stream' ]"
	else
		report "saturn:disc-change" SKIP "no second Saturn disc (SATURN_GAME2)"
	fi

	# a CHD made from the cue sheet is the same disc: the same run, far enough
	# into the game that it plays the disc's audio tracks (a CHD holds audio
	# with its bytes the other way round, and a run that never played any
	# would not notice them left that way), then the savestate tests on it
	if [ -n "$game_chd" ] && [ -f "$game_chd" ]; then
		folder ss-chd '{"machine":"saturn"}' disc "$game_chd"; sat_firmware ss-chd
		chdrun="--frames 2400 --report 50 --press 11:900:10 --press 11:1300:10 --press 11:1500:10 --press 10:1700:10 --press 10:1900:10"
		nat ss-long ss $chdrun
		box ss-chd ss-chd $chdrun
		box ss-chd-session ss-chd $chdrun --session
		box ss-chd-rewind ss-chd --frames 2400 --report 5 --press 11:900:10 --rewind
		for n in ss-long ss-chd ss-chd-session; do stream "$work/$n.out" > "$work/$n.stream"; done
		check "saturn:chd" "the game from a CHD in the sandbox prints the $(wc -l < "$work/ss-long.stream") digests the game from its cue sheet prints natively, over 2400 frames with presses" \
			same "$work/ss-long.stream" "$work/ss-chd.stream"
		check "saturn:chd-states" "from the CHD, a state moved to a new sandbox half way changes nothing" \
			sh -c "cmp -s '$work/ss-chd.stream' '$work/ss-chd-session.stream' && [ -s '$work/ss-chd-session.stream' ]" 
		check "saturn:chd-rewind" "from the CHD, a state kept at frame 1200 and loaded at 1800: the frames after the load repeat those after the save" \
			repeats "$work/ss-chd-rewind.out" 1200 1800 600 5
	else
		for t in chd chd-states chd-rewind; do report "saturn:$t" SKIP "no CHD of the Saturn game (SATURN_GAME_CHD)"; done
	fi

	# save data: out, changed, in again, and out unchanged
	if [ -s "$work/ss-saves/saturn.bkr" ]; then
		mkdir -p "$work/mine"
		python3 - "$work/ss-saves/saturn.bkr" "$work/mine/mine.bkr" <<'PY'
import sys
b = bytearray(open(sys.argv[1], "rb").read())
b[0x4000:0x4004] = b"\xa5\x5a\xc3\x3c"
open(sys.argv[2], "wb").write(b)
PY
		folder ss-saved '{"machine":"saturn"}' disc "$cue" "$work/mine/mine.bkr"; sat_firmware ss-saved
		box ss-saved ss-saved --frames 300 --report 300 --savedata-out "$work/ss-saves2"
		check "saturn:save-data" "the backup memory goes out as a file of 32768 bytes that begins \"$(head -c 16 "$work/ss-saves/saturn.bkr")\"; a changed copy given to a project comes out as it went in" \
			sh -c "[ \"\$(head -c 16 '$work/ss-saves/saturn.bkr')\" = 'BackUpRam Format' ] && cmp -s '$work/mine/mine.bkr' '$work/ss-saves2/saturn.bkr' && ! cmp -s '$work/ss-saves/saturn.bkr' '$work/ss-saves2/saturn.bkr'"
	else
		report "saturn:save-data" FAIL "no backup memory was exported"
	fi

	# the firmware: the core names the BIOS the disc's region uses, and a
	# console without it does not start
	"$native" "$work/ss" --suggest > "$work/ss.suggest" 2> /dev/null
	check "saturn:firmware-asked" "before anything is loaded the core names the two BIOS files, each with the settings it is needed under" \
		python3 -c "
import json, sys
f = json.load(open(sys.argv[1]))['firmware']
ids = [x['id'] for x in f]
sys.exit(0 if ids[:2] == ['saturn_jp.bin', 'saturn_na_eu.bin'] and all('requiredWhen' in x for x in f) else 1)" "$work/ss.suggest"
	folder ss-nobios '{"machine":"saturn"}' disc "$cue"
	nat ss-nobios ss-nobios --frames 1
	check "saturn:firmware-missing" "without its BIOS the console is refused, by the file's name" \
		grep -q 'Init failed.*saturn_.*\.bin' "$work/ss-nobios.out" "$work/ss-nobios.err"
else
	for t in runs pad sandbox controls bus bus-memories bus-write lag state-every-frame state-other-box state-rewind setting devices lid disc-change chd chd-states chd-rewind save-data firmware-asked firmware-missing; do
		report "saturn:$t" SKIP "no Saturn game with its two BIOS files (SATURN_GAME, SATURN_BIOS_JP, SATURN_BIOS_NA_EU)"
	done
fi
# ------------------------------------------------- the PC-FX, with a game
fxcue="$(ls "$fxgame"/*.cue 2> /dev/null | head -1)"
if [ -n "$fxcue" ] && [ -f "$fxbios" ]; then
	folder fx '{"machine":"pcfx"}' disc "$fxcue"; ln -sf "$fxbios" "$work/fx/pcfx.rom"
	# button I, then Run, then I three times, five seconds apart: past the
	# BIOS's screen and into most games
	fxrun="--frames 3000 --report 50 --press 0:1400:10 --press 7:1700:10 --press 0:2000:10 --press 0:2300:10 --press 0:2600:10"
	mkdir -p "$work/fx-saves"
	nat fx-idle fx --frames 3000 --report 50
	nat fx fx $fxrun --list-panel --savedata-out "$work/fx-saves"
	box fx-box fx $fxrun
	for n in fx fx-idle fx-box; do stream "$work/$n.out" > "$work/$n.stream"; done
	pictures="$(awk '{print $7}' "$work/fx.stream" | sort -u | wc -l)"
	sounds="$(awk '{print $10}' "$work/fx.stream" | sort -u | wc -l)"
	check "pcfx:runs" "the game runs: $pictures different pictures and $sounds different stretches of sound in 60 reports" [ "$pictures" -gt 5 -a "$sounds" -gt 5 ]
	check "pcfx:pad" "the pad's buttons change the run (the idle run's digests differ)" differ "$work/fx.stream" "$work/fx-idle.stream"
	check "pcfx:sandbox" "native and sandbox print the same $(wc -l < "$work/fx.stream") digests of RAM, picture and sound, with presses" \
		same "$work/fx.stream" "$work/fx-box.stream"
	check "pcfx:controls" "port 1's pad of 14 controls and the drive's lid are live, and nothing of port 2, which starts empty" \
		sh -c "[ \"\$(grep -c '^panel .* active\$' '$work/fx.out')\" = 15 ] && ! grep -q \"'P2 I' active\" '$work/fx.out'"
	lag="$(field "$work/fx.out" lag)"
	check "pcfx:lag" "lag frames are counted while the game loads ($lag of 3000), and not on every frame" \
		[ "${lag:-0}" -gt 0 -a "${lag:-0}" -lt 3000 ]
	box fx-rerecord fx --frames 1500 --report 50 --press 0:1400:10 --rerecord
	box fx-short fx --frames 1500 --report 50 --press 0:1400:10
	box fx-session fx $fxrun --session
	# no press after the state is kept: what follows the load can only repeat
	# what followed the save under the same input
	box fx-rewind fx --frames 3000 --report 5 --press 0:1400:10 --rewind
	for n in fx-rerecord fx-short fx-session; do stream "$work/$n.out" > "$work/$n.stream"; done
	check "pcfx:state-every-frame" "a state saved and loaded every frame for 1500 frames changes nothing" same "$work/fx-short.stream" "$work/fx-rerecord.stream"
	check "pcfx:state-other-box" "a state moved to a new sandbox half way changes nothing" same "$work/fx-box.stream" "$work/fx-session.stream"
	check "pcfx:state-rewind" "a state kept at frame 1500 and loaded at 2250, while the game plays from its disc: the frames after the load repeat those after the save" \
		repeats "$work/fx-rewind.out" 1500 2250 750 5
	save_round_trip "pcfx:save-data" pcfx disc "$fxcue" "$work/fx-saves" sav PCFXSram "the console's backup memory (labelled PCFXSram)"
	save_round_trip "pcfx:save-pack" pcfx disc "$fxcue" "$work/fx-saves" fxb PCFXCard "the memory pack's memory (labelled PCFXCard)"
	fxcue2="$(ls "$fxgame2"/*.cue 2> /dev/null | head -1)"
	if [ -n "$fxcue2" ]; then
		folder fx2 '{"machine":"pcfx"}' disc "$fxcue"; ln -sf "$fxbios" "$work/fx2/pcfx.rom"
		for f in "$fxgame2"/*; do ln -sf "$f" "$work/fx2/$(basename "$f")"; done
		printf '{"disc":["%s","%s"],"savedata":[]}' "$(basename "$fxcue")" "$(basename "$fxcue2")" > "$work/fx2/slots"
		nat fx2-list fx2 --frames 1 --list-panel
		next="$(awk -v n="'Next Disc'" 'index($0, n) && $1 == "panel" { print $2; exit }' "$work/fx2-list.out")"
		swap2="$(awk -v n="'Disc Swap'" 'index($0, n) && $1 == "panel" { print $2; exit }' "$work/fx2-list.out")"
		# the lid goes up before the BIOS has looked at the disc
		nat fx2-next fx2 --frames 1500 --report 100 --press "$swap2:100:120" --dump-domain RAM "$work/fx2-next.ram"
		nat fx2-same fx2 --frames 1500 --report 100 --press "$swap2:100:120" --press "$next:110:5" --press "$next:130:5" --dump-domain RAM "$work/fx2-same.ram"
		box fx2-box fx2 --frames 1500 --report 100 --press "$swap2:100:120"
		for n in fx2-next fx2-same fx2-box; do stream "$work/$n.out" > "$work/$n.stream"; done
		check "pcfx:disc-change" "with two discs the selector is live; the lid alone closes on the second disc and the selector moved there and back closes it on the first (the two runs end differently), the same in the sandbox" \
			sh -c "grep -q \"'Next Disc' active\" '$work/fx2-list.out' && ! grep -q \"'Next Disc' active\" '$work/fx.out' && [ \"\$(tail -1 '$work/fx2-next.stream')\" != \"\$(tail -1 '$work/fx2-same.stream')\" ] && cmp -s '$work/fx2-next.stream' '$work/fx2-box.stream' && [ -s '$work/fx2-next.stream' ]"
	else
		report "pcfx:disc-change" SKIP "no second PC-FX disc (PCFX_GAME2)"
	fi
	# a CHD made from the cue sheet is the same disc
	if [ -n "$fxgame_chd" ] && [ -f "$fxgame_chd" ]; then
		folder fx-chd '{"machine":"pcfx"}' disc "$fxgame_chd"; ln -sf "$fxbios" "$work/fx-chd/pcfx.rom"
		box fx-chd fx-chd $fxrun
		stream "$work/fx-chd.out" > "$work/fx-chd.stream"
		check "pcfx:chd" "the game from a CHD in the sandbox prints the $(wc -l < "$work/fx.stream") digests the game from its cue sheet prints natively, over 3000 frames with presses" \
			same "$work/fx.stream" "$work/fx-chd.stream"
	else
		report "pcfx:chd" SKIP "no CHD of the PC-FX game (PCFX_GAME_CHD)"
	fi
	folder fx-nobios '{"machine":"pcfx"}' disc "$fxcue"
	nat fx-nobios fx-nobios --frames 1
	check "pcfx:firmware-missing" "without its BIOS the console is refused, by the file's name" \
		grep -q 'Init failed.*pcfx\.rom' "$work/fx-nobios.out" "$work/fx-nobios.err"
else
	for t in runs pad sandbox controls lag state-every-frame state-other-box state-rewind save-data save-pack disc-change chd firmware-missing; do
		report "pcfx:$t" SKIP "no PC-FX game with the console's BIOS (PCFX_GAME, PCFX_BIOS)"
	done
fi

# ------------------------------------------------- the Lynx, with a game
lnx="$(ls "$lxgame"/*.lnx 2> /dev/null | head -1)"
if [ -n "$lnx" ] && [ -f "$lxboot" ]; then
	folder lx '{"machine":"lynx"}' cart "$lnx"; ln -sf "$lxboot" "$work/lx/lynxboot.img"
	# A five times, five seconds apart, and the pad between
	lxrun="--frames 2400 --report 50 --press 0:700:5 --press 0:1000:5 --press 5:1150:30 --press 0:1300:5 --press 7:1450:30 --press 0:1600:5 --press 0:1900:5"
	nat lx-idle lx --frames 2400 --report 50
	nat lx lx $lxrun --list-panel
	box lx-box lx $lxrun
	for n in lx lx-idle lx-box; do stream "$work/$n.out" > "$work/$n.stream"; done
	pictures="$(awk '{print $7}' "$work/lx.stream" | sort -u | wc -l)"
	check "lynx:runs" "the game runs: $pictures different pictures in 48 reports" [ "$pictures" -gt 5 ]
	check "lynx:pad" "A and the pad change the run (the idle run's digests differ)" differ "$work/lx.stream" "$work/lx-idle.stream"
	check "lynx:sandbox" "native and sandbox print the same $(wc -l < "$work/lx.stream") digests of RAM, picture and sound, with presses" \
		same "$work/lx.stream" "$work/lx-box.stream"
	check "lynx:controls" "the console's 9 buttons are live" [ "$(grep -c "^panel .* active\$" "$work/lx.out")" = 9 ]
	lag="$(field "$work/lx.out" lag)"
	check "lynx:lag" "lag frames are counted ($lag of 2400), and not on every frame" [ "${lag:-0}" -gt 0 -a "${lag:-0}" -lt 2400 ]
	box lx-rerecord lx $lxrun --rerecord
	box lx-session lx $lxrun --session
	box lx-rewind lx --frames 2400 --report 5 --press 0:700:5 --press 0:1000:5 --rewind
	stream "$work/lx-rerecord.out" > "$work/lx-rerecord.stream"
	stream "$work/lx-session.out" > "$work/lx-session.stream"
	check "lynx:state-every-frame" "a state saved and loaded every frame changes nothing" same "$work/lx-box.stream" "$work/lx-rerecord.stream"
	check "lynx:state-other-box" "a state moved to a new sandbox half way changes nothing" same "$work/lx-box.stream" "$work/lx-session.stream"
	check "lynx:state-rewind" "a state kept at frame 1200 and loaded at 1800: the frames after the load repeat those after the save" \
		repeats "$work/lx-rewind.out" 1200 1800 600 5
	folder lx-noboot '{"machine":"lynx"}' cart "$lnx"
	nat lx-noboot lx-noboot --frames 1
	check "lynx:firmware-missing" "without its boot ROM the console is refused, by the file's name" \
		grep -q 'Init failed.*lynxboot\.img' "$work/lx-noboot.out" "$work/lx-noboot.err"
else
	for t in runs pad sandbox controls lag state-every-frame state-other-box state-rewind firmware-missing; do
		report "lynx:$t" SKIP "no Lynx game with the console's boot ROM (LYNX_GAME, LYNX_BOOT)"
	done
fi

# ------------------------------------------------- the ST-V arcade board, with a game
svzip="$(ls "$svgame"/*.zip 2> /dev/null | head -1)"
if [ -n "$svzip" ] && [ -f "$svbios" ]; then
	folder sv '{"machine":"stv"}' romset "$svzip"; ln -sf "$svbios" "$work/sv/stvbios.zip"
	# a coin, Start, Button 1 three times, then the stick and the three buttons
	svrun="--frames 3000 --report 50 --press 26:1500:5 --press 4:1700:5 --press 5:1900:5 --press 5:2100:5 --press 5:2300:5 --press 3:2500:120 --press 5:2650:10 --press 6:2700:10 --press 7:2750:10"
	mkdir -p "$work/sv-save"
	nat sv-idle sv --frames 3000 --report 50
	nat sv-coin sv --frames 3000 --report 50 --press 26:1500:5
	nat sv sv $svrun --list-panel --savedata-out "$work/sv-save"
	box sv-box sv $svrun
	for n in sv sv-idle sv-coin sv-box; do stream "$work/$n.out" > "$work/$n.stream"; done
	pictures="$(awk '{print $7}' "$work/sv.stream" | sort -u | wc -l)"
	check "stv:runs" "the game is found in its ROM set, the board starts from the BIOS set and the game runs: $pictures different pictures in 60 reports" [ "$pictures" -gt 5 ]
	check "stv:coin" "a coin changes the run (the idle run's digests differ)" differ "$work/sv-coin.stream" "$work/sv-idle.stream"
	check "stv:pad" "Start, the stick and the buttons change the run from the one with only the coin" differ "$work/sv.stream" "$work/sv-coin.stream"
	check "stv:sandbox" "native and sandbox print the same $(wc -l < "$work/sv.stream") digests of RAM, picture and sound, with presses" \
		same "$work/sv.stream" "$work/sv-box.stream"
	check "stv:controls" "the cabinet's 26 buttons are live: two players' sticks, six buttons and Start, Test, Service, Pause and Coin" \
		[ "$(grep -c "^panel .* active\$" "$work/sv.out")" = 26 ]
	lag="$(field "$work/sv.out" lag)"
	check "stv:lag" "lag frames are counted ($lag of 3000), and not on every frame" [ "${lag:-0}" -gt 0 -a "${lag:-0}" -lt 3000 ]
	box sv-rerecord sv $svrun --rerecord
	box sv-session sv $svrun --session
	box sv-rewind sv --frames 4000 --report 5 --press 26:1500:5 --press 4:1700:5 --press 5:1900:5 --rewind
	stream "$work/sv-rerecord.out" > "$work/sv-rerecord.stream"
	stream "$work/sv-session.out" > "$work/sv-session.stream"
	check "stv:state-every-frame" "a state saved and loaded every frame changes nothing" same "$work/sv-box.stream" "$work/sv-rerecord.stream"
	check "stv:state-other-box" "a state moved to a new sandbox half way changes nothing" same "$work/sv-box.stream" "$work/sv-session.stream"
	check "stv:state-rewind" "a state kept at frame 2000 and loaded at 3000: the frames after the load repeat those after the save" \
		repeats "$work/sv-rewind.out" 2000 3000 1000 5
	folder sv-na '{"machine":"stv","stv.region":"na"}' romset "$svzip"; ln -sf "$svbios" "$work/sv-na/stvbios.zip"
	nat sv-na sv-na --frames 3000 --report 50
	stream "$work/sv-na.out" > "$work/sv-na.stream"
	check "stv:region" "with the Region setting on North America the board starts from another BIOS of the set: the game runs and its digests differ" \
		sh -c "[ \"\$(awk '{print \$7}' '$work/sv-na.stream' | sort -u | wc -l)\" -gt 5 ] && ! cmp -s '$work/sv-na.stream' '$work/sv-idle.stream'"
	check "stv:save-data" "the board's backup memory and its settings memory go out as files of 32768 and 128 bytes, and the backup memory holds what the game wrote" \
		sh -c "[ \"\$(tr -d '\\0' < '$work/sv-save/stv.bkr' | wc -c)\" -gt 16 ] && [ \"\$(wc -c < '$work/sv-save/stv.bkr')\" = 32768 ] && [ \"\$(wc -c < '$work/sv-save/stv.seep')\" = 128 ]"
	save_round_trip stv:save-backup stv romset "$svzip" "$work/sv-save" bkr "" "the backup memory" 1
	save_round_trip stv:save-settings stv romset "$svzip" "$work/sv-save" seep "SEGA" "the settings memory" 1
	folder sv-nobios '{"machine":"stv"}' romset "$svzip"
	nat sv-nobios sv-nobios --frames 1
	check "stv:firmware-missing" "without its BIOS set the board is refused, by the file's name" \
		grep -q 'Init failed.*stvbios\.zip' "$work/sv-nobios.out" "$work/sv-nobios.err"
	mkdir -p "$work/sv-nogame-src"
	python3 -c "
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as z: z.writestr('readme.txt', 'not a game')
with zipfile.ZipFile(sys.argv[2], 'w', zipfile.ZIP_DEFLATED) as z: z.writestr('other.ic8', bytes(524288))
" "$work/sv-nogame-src/notagame.zip" "$work/sv-otherbios.zip"
	folder sv-nogame '{"machine":"stv"}' romset "$work/sv-nogame-src/notagame.zip"; ln -sf "$svbios" "$work/sv-nogame/stvbios.zip"
	nat sv-nogame sv-nogame --frames 1
	check "stv:not-a-game" "a zip that holds no ST-V game is refused, and the message says what a ROM set is" \
		grep -q 'Init failed.*error.stv_unknown' "$work/sv-nogame.out" "$work/sv-nogame.err"
	folder sv-otherbios '{"machine":"stv"}' romset "$svzip"; ln -sf "$work/sv-otherbios.zip" "$work/sv-otherbios/stvbios.zip"
	nat sv-otherbios sv-otherbios --frames 1
	check "stv:bios-by-contents" "a BIOS set without the region's BIOS is refused, and the message names the file MAME calls it" \
		grep -q 'Init failed.*error.stv_bios_missing.*epr-20091\.ic8' "$work/sv-otherbios.out" "$work/sv-otherbios.err"
else
	for t in runs coin pad sandbox controls lag state-every-frame state-other-box state-rewind region save-data save-backup save-settings firmware-missing not-a-game bios-by-contents; do
		report "stv:$t" SKIP "no ST-V game with the board's BIOS set (STV_GAME, STV_BIOS)"
	done
fi
svzip_up="$(ls "$svgame_up"/*.zip 2> /dev/null | head -1)"
if [ -n "$svzip_up" ] && [ -f "$svbios" ]; then
	folder sv-up '{"machine":"stv"}' romset "$svzip_up"; ln -sf "$svbios" "$work/sv-up/stvbios.zip"
	svuprun="--frames 3000 --report 100 --press 26:2000:5 --press 4:2200:5 --press 5:2400:300"
	nat sv-up sv-up $svuprun
	box sv-up-box sv-up $svuprun
	stream "$work/sv-up.out" > "$work/sv-up.stream"; stream "$work/sv-up-box.out" > "$work/sv-up-box.stream"
	size="$(field "$work/sv-up.out" vid)"
	check "stv:upright" "a game whose monitor stands on its side is shown turned: its picture is $size, taller than wide, and the sandbox draws what the native build does" \
		sh -c "[ '${size%x*}' -lt '${size#*x}' ] && cmp -s '$work/sv-up.stream' '$work/sv-up-box.stream'"
else
	report "stv:upright" SKIP "no ST-V game with an upright monitor (STV_GAME_UPRIGHT) with the board's BIOS set"
fi
svzip_hm="$(ls "$svgame_hammer"/*.zip 2> /dev/null | head -1)"
if [ -n "$svzip_hm" ] && [ -f "$svbios" ]; then
	folder sv-hm '{"machine":"stv"}' romset "$svzip_hm"; ln -sf "$svbios" "$work/sv-hm/stvbios.zip"
	# a coin, then the hammer at the middle of the table, twice
	svhmcoin="--frames 4800 --report 100 --axis 0:32768:0:4800 --axis 1:32768:0:4800 --press 26:4000:5"
	nat sv-hm-coin sv-hm $svhmcoin
	nat sv-hm sv-hm $svhmcoin --press 11:4300:4 --press 11:4500:4 --list-panel
	box sv-hm-box sv-hm $svhmcoin --press 11:4300:4 --press 11:4500:4
	for n in sv-hm sv-hm-coin sv-hm-box; do stream "$work/$n.out" > "$work/$n.stream"; done
	check "stv:hammer" "a game played with a hammer has the hammer and no sticks ($(grep -c "^panel .* active\$" "$work/sv-hm.out") buttons and $(grep -c "^axis .* active\$" "$work/sv-hm.out") axes live); a hit changes the run, and the sandbox gives the native build's digests" \
		sh -c "[ \"\$(grep -c '^panel .* active\$' '$work/sv-hm.out')\" = 5 ] && [ \"\$(grep -c '^axis .* active\$' '$work/sv-hm.out')\" = 2 ] && ! cmp -s '$work/sv-hm.stream' '$work/sv-hm-coin.stream' && cmp -s '$work/sv-hm.stream' '$work/sv-hm-box.stream'"
else
	report "stv:hammer" SKIP "no ST-V game played with a hammer (STV_GAME_HAMMER) with the board's BIOS set"
fi

# ------------------------------------------------- the Virtual Boy, with a game
vbrom="$(ls "$vbgame"/*.vb "$vbgame"/*.vboy 2> /dev/null | head -1)"
if [ -n "$vbrom" ]; then
	folder vg '{"machine":"virtualboy"}' cart "$vbrom"
	# Start and A in turn, five seconds apart
	vgrun="--frames 3000 --report 50 --press 10:600:5 --press 10:900:5 --press 10:1200:5 --press 0:1500:5 --press 10:1800:5 --press 0:2100:5 --press 10:2400:5"
	nat vg-idle vg --frames 3000 --report 50
	nat vg vg $vgrun
	box vg-box vg $vgrun
	for n in vg vg-idle vg-box; do stream "$work/$n.out" > "$work/$n.stream"; done
	pictures="$(awk '{print $7}' "$work/vg.stream" | sort -u | wc -l)"
	check "vb-game:runs" "the game runs: $pictures different pictures in 60 reports" [ "$pictures" -gt 5 ]
	check "vb-game:pad" "Start and A change the run (the idle run's digests differ)" differ "$work/vg.stream" "$work/vg-idle.stream"
	check "vb-game:sandbox" "native and sandbox print the same $(wc -l < "$work/vg.stream") digests of RAM, picture and sound, with presses" \
		same "$work/vg.stream" "$work/vg-box.stream"
	box vg-rerecord vg $vgrun --rerecord
	box vg-session vg $vgrun --session
	box vg-rewind vg --frames 3000 --report 5 --press 10:600:5 --press 10:900:5 --press 10:1200:5 --rewind
	stream "$work/vg-rerecord.out" > "$work/vg-rerecord.stream"
	stream "$work/vg-session.out" > "$work/vg-session.stream"
	check "vb-game:state-every-frame" "a state saved and loaded every frame changes nothing" same "$work/vg-box.stream" "$work/vg-rerecord.stream"
	check "vb-game:state-other-box" "a state moved to a new sandbox half way changes nothing" same "$work/vg-box.stream" "$work/vg-session.stream"
	check "vb-game:state-rewind" "a state kept at frame 1500 and loaded at 2250: the frames after the load repeat those after the save" \
		repeats "$work/vg-rewind.out" 1500 2250 750 5
	# (the save file test is "vb:save-data": a game may wipe a save it does not
	# recognise, as Virtual Boy Wario Land does)
else
	for t in runs pad sandbox state-every-frame state-other-box state-rewind; do
		report "vb-game:$t" SKIP "no Virtual Boy game (VB_GAME)"
	done
fi

# ------------------------------------------------- in Chimera's engine
engine="$chimera_root/build/meson-linux/chimera-run"
pkg="$chimera_root/build/Cores/mednafen.chimeraCore"
if [ -n "$chimera_root" ] && [ -x "$engine" ] && [ -f "$pkg" ]; then
	mk="$root/tests/make-project.py"
	python3 "$mk" "$pkg" "$work/vb.chimeraProject" 300 machine=virtualboy "panel=$work/vb.out" \
		"press=P1 A:100:40" -- "cart=$work/vbgame/chimera-test.vb" > "$work/vb.project.log" 2>&1
	python3 "$mk" "$pkg" "$work/vb-idle.chimeraProject" 300 machine=virtualboy "panel=$work/vb.out" \
		-- "cart=$work/vbgame/chimera-test.vb" >> "$work/vb.project.log" 2>&1
	"$engine" --project "$work/vb.chimeraProject" "$pkg" --files "$work/vbgame" --save-state "120=$work/vb-engine.state" > "$work/vb.engine" 2>&1
	"$engine" --project "$work/vb-idle.chimeraProject" "$pkg" --files "$work/vbgame" --save-state "120=$work/vb-idle-engine.state" > "$work/vb-idle.engine" 2>&1
	check "engine:vb" "a Virtual Boy project plays a 300-frame movie in Chimera's engine, and the movie's A held at frame 120 makes another state than the idle movie's" \
		sh -c "grep -q '^frames=300' '$work/vb.engine' && grep -q '^frames=300' '$work/vb-idle.engine' && [ -s '$work/vb-engine.state' ] && ! cmp -s '$work/vb-engine.state' '$work/vb-idle-engine.state'"
	if [ -n "$cue" ] && [ -f "$bios_na" ] && [ -f "$bios_jp" ]; then
		# which BIOS this disc starts with is the core's own answer
		id="$(python3 -c "
import json, sys
n = json.load(open(sys.argv[1]))['note']
print('saturn_jp.bin' if n.startswith('suggest.japan') else 'saturn_na_eu.bin')" "$work/ss.suggest")"
		[ "$id" = saturn_jp.bin ] && bios="$bios_jp" || bios="$bios_na"
		python3 "$mk" "$pkg" "$work/ss.chimeraProject" 1500 machine=saturn "panel=$work/ss.out" \
			"press=P1 Start:900:10" "press=P1 Start:1300:10" "firmware=$id=$bios" -- "disc=$cue" > "$work/ss.project.log" 2>&1
		python3 "$mk" "$pkg" "$work/ss-idle.chimeraProject" 1500 machine=saturn "panel=$work/ss.out" \
			"firmware=$id=$bios" -- "disc=$cue" >> "$work/ss.project.log" 2>&1
		"$engine" --project "$work/ss.chimeraProject" "$pkg" --files "$game" --firmware "$id=$bios" \
			--screenshot "1499=$work/ss.tga" --ram-search-bench "System Bus" > "$work/ss.engine" 2>&1
		"$engine" --project "$work/ss-idle.chimeraProject" "$pkg" --files "$game" --firmware "$id=$bios" \
			--screenshot "1499=$work/ss-idle.tga" > "$work/ss-idle.engine" 2>&1
		check "engine:saturn" "a Saturn project with its BIOS as firmware plays a 1500-frame movie in Chimera's engine, and the movie's presses of Start change the last picture" \
			sh -c "grep -q '^frames=1500' '$work/ss.engine' && grep -q '^frames=1500' '$work/ss-idle.engine' && [ -s '$work/ss.tga' ] && ! cmp -s '$work/ss.tga' '$work/ss-idle.tga'"
		# the two work RAMs (2 MB), the sound, VDP1 and VDP2 memories (512 KB each)
		# and the colour memory (4 KB)
		check "engine:saturn-bus" "Chimera's RAM search reads the Saturn's bus: $(grep -o '[0-9]* live ranges, [0-9]* of [0-9]* bytes searched' "$work/ss.engine")" \
			grep -q "6 live ranges, 3674112 of 134217728 bytes searched, every candidate live and reading what the bus peeks" "$work/ss.engine"
		if [ -n "$game_chd" ] && [ -f "$game_chd" ]; then
			python3 "$mk" "$pkg" "$work/ss-chd.chimeraProject" 1500 machine=saturn "panel=$work/ss.out" \
				"press=P1 Start:900:10" "press=P1 Start:1300:10" "firmware=$id=$bios" -- "disc=$game_chd" > "$work/ss-chd.project.log" 2>&1
			"$engine" --project "$work/ss-chd.chimeraProject" "$pkg" --files "$(dirname "$game_chd")" --firmware "$id=$bios" \
				--screenshot "1499=$work/ss-chd.tga" > "$work/ss-chd.engine" 2>&1
			check "engine:saturn-chd" "a project whose disc is the CHD plays the same movie in Chimera's engine and ends on the picture the cue sheet's project ends on" \
				sh -c "grep -q '^frames=1500' '$work/ss-chd.engine' && cmp -s '$work/ss.tga' '$work/ss-chd.tga'"
		else
			report "engine:saturn-chd" SKIP "no CHD of the Saturn game (SATURN_GAME_CHD)"
		fi
	else
		report "engine:saturn" SKIP "no Saturn game with its BIOS files"
		report "engine:saturn-bus" SKIP "no Saturn game with its BIOS files"
		report "engine:saturn-chd" SKIP "no Saturn game with its BIOS files"
	fi
	if [ -n "$fxcue" ] && [ -f "$fxbios" ]; then
		python3 "$mk" "$pkg" "$work/fx.chimeraProject" 2000 machine=pcfx "panel=$work/fx.out" \
			"press=P1 I:1400:10" "press=P1 Run:1700:10" "firmware=pcfx.rom=$fxbios" -- "disc=$fxcue" > "$work/fx.project.log" 2>&1
		python3 "$mk" "$pkg" "$work/fx-idle.chimeraProject" 2000 machine=pcfx "panel=$work/fx.out" \
			"firmware=pcfx.rom=$fxbios" -- "disc=$fxcue" >> "$work/fx.project.log" 2>&1
		"$engine" --project "$work/fx.chimeraProject" "$pkg" --files "$fxgame" --firmware "pcfx.rom=$fxbios" \
			--screenshot "1999=$work/fx.tga" > "$work/fx.engine" 2>&1
		"$engine" --project "$work/fx-idle.chimeraProject" "$pkg" --files "$fxgame" --firmware "pcfx.rom=$fxbios" \
			--screenshot "1999=$work/fx-idle.tga" > "$work/fx-idle.engine" 2>&1
		check "engine:pcfx" "a PC-FX project with its BIOS as firmware plays a 2000-frame movie in Chimera's engine, and the movie's presses change the last picture" \
			sh -c "grep -q '^frames=2000' '$work/fx.engine' && grep -q '^frames=2000' '$work/fx-idle.engine' && [ -s '$work/fx.tga' ] && ! cmp -s '$work/fx.tga' '$work/fx-idle.tga'"
	else
		report "engine:pcfx" SKIP "no PC-FX game with the console's BIOS"
	fi
	if [ -n "$lnx" ] && [ -f "$lxboot" ]; then
		python3 "$mk" "$pkg" "$work/lx.chimeraProject" 1200 machine=lynx "panel=$work/lx.out" \
			"press=P1 A:700:5" "press=P1 A:1000:5" "firmware=lynxboot.img=$lxboot" -- "cart=$lnx" > "$work/lx.project.log" 2>&1
		python3 "$mk" "$pkg" "$work/lx-idle.chimeraProject" 1200 machine=lynx "panel=$work/lx.out" \
			"firmware=lynxboot.img=$lxboot" -- "cart=$lnx" >> "$work/lx.project.log" 2>&1
		"$engine" --project "$work/lx.chimeraProject" "$pkg" --files "$lxgame" --firmware "lynxboot.img=$lxboot" \
			--save-state "1199=$work/lx-engine.state" > "$work/lx.engine" 2>&1
		"$engine" --project "$work/lx-idle.chimeraProject" "$pkg" --files "$lxgame" --firmware "lynxboot.img=$lxboot" \
			--save-state "1199=$work/lx-idle-engine.state" > "$work/lx-idle.engine" 2>&1
		check "engine:lynx" "a Lynx project with its boot ROM as firmware plays a 1200-frame movie in Chimera's engine, and the movie's presses of A make another state than the idle movie's" \
			sh -c "grep -q '^frames=1200' '$work/lx.engine' && grep -q '^frames=1200' '$work/lx-idle.engine' && [ -s '$work/lx-engine.state' ] && ! cmp -s '$work/lx-engine.state' '$work/lx-idle-engine.state'"
	else
		report "engine:lynx" SKIP "no Lynx game with the console's boot ROM"
	fi
	if [ -n "$svzip" ] && [ -f "$svbios" ]; then
		python3 "$mk" "$pkg" "$work/sv.chimeraProject" 2400 machine=stv "panel=$work/sv.out" \
			"press=Coin:1500:5" "press=P1 Start:1700:5" "press=P1 Button 1:1900:5" "firmware=stvbios.zip=$svbios" -- "romset=$svzip" > "$work/sv.project.log" 2>&1
		python3 "$mk" "$pkg" "$work/sv-idle.chimeraProject" 2400 machine=stv "panel=$work/sv.out" \
			"firmware=stvbios.zip=$svbios" -- "romset=$svzip" >> "$work/sv.project.log" 2>&1
		"$engine" --project "$work/sv.chimeraProject" "$pkg" --files "$svgame" --firmware "stvbios.zip=$svbios" \
			--screenshot "2399=$work/sv.tga" > "$work/sv.engine" 2>&1
		"$engine" --project "$work/sv-idle.chimeraProject" "$pkg" --files "$svgame" --firmware "stvbios.zip=$svbios" \
			--screenshot "2399=$work/sv-idle.tga" > "$work/sv-idle.engine" 2>&1
		check "engine:stv" "an ST-V project with its ROM set and the BIOS set as firmware plays a 2400-frame movie in Chimera's engine, and the movie's coin and Start change the last picture" \
			sh -c "grep -q '^frames=2400' '$work/sv.engine' && grep -q '^frames=2400' '$work/sv-idle.engine' && [ -s '$work/sv.tga' ] && ! cmp -s '$work/sv.tga' '$work/sv-idle.tga'"
	else
		report "engine:stv" SKIP "no ST-V game with the board's BIOS set"
	fi
else
	for t in vb saturn saturn-bus saturn-chd pcfx lynx stv; do
		report "engine:$t" SKIP "set CHIMERA_ROOT to a Chimera checkout with build/meson-linux/chimera-run and this core's package (waterbox/build-package.sh -r <it>)"
	done
fi

printf '\n%d passed, %d failed, %d skipped\n' "$ok" "$failed" "$skipped"
[ "$ok" -gt 0 ] || { echo "NOTHING RAN"; exit 1; }
[ "$failed" -eq 0 ]
