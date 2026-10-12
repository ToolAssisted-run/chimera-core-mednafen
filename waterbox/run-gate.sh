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
# tests/games-local/vfremix-chd when not given). SATURN_BIOS_JP and SATURN_BIOS_NA_EU are the two BIOS files
# (tests/roms-local/sega_101.bin and mpr-17933.bin when not given).
#
# Needs the native build (meson setup build/meson-native ... && ninja) and
# the sandboxed core (waterbox/setup-guest.sh && ninja -C build/meson-guest):
# docs/BUILDING.md.
#
# WHAT RUNS WITH NO FILES OF YOURS. No BIOS and no game may be put in this
# repository or on a CI runner. The Virtual Boy needs no BIOS, and
# tests/make-vb-program.py assembles a small program for it, so the "vb:"
# tests run everywhere: the processor runs, the pad reaches the program,
# its reads of the pad are seen, and the sandbox gives the native build's
# results with savestates. The Saturn tests need a game and its BIOS and say
# SKIP without them. The PC-FX and the Lynx have no test: no game of theirs
# has been run.
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

# ------------------------------------------------- what is refused
mkdir -p "$work/none"
printf '{}' > "$work/none/slots"
printf '{"machine":"saturn"}' > "$work/none/settings"
nat none none --frames 1
check "refused:no-game" "a Saturn with no disc is refused, and says so" grep -q "no disc was given" "$work/none.out" "$work/none.err"
printf '{"machine":"dreamcast"}' > "$work/none/settings"
nat nomachine none --frames 1
check "refused:machine" "a machine this core does not have is refused by name" grep -q 'unknown machine "dreamcast"' "$work/nomachine.out" "$work/nomachine.err"

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
	check "saturn:controls" "two pads of 13 buttons, Reset and the drive's lid are live, of the 594 buttons the Saturn declares" \
		[ "$(grep -c "^panel .* active\$" "$work/ss.out")" = 28 ]
	# the BIOS copies the disc's header to 0x06002000; the Saturn keeps its RAM
	# as words, so this also says the bus hands bytes out in the console's order
	check "saturn:bus" "the bus reads \"$(tr -d '\0' < "$work/ss.header" 2> /dev/null)\" at 0x06002000, where the BIOS puts the disc's header" \
		[ "$(cat "$work/ss.header" 2> /dev/null)" = "SEGA SEGASATURN " ]
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
	folder ss-ports '{"machine":"saturn","ss.input.port1":"3dpad","ss.input.port2":"mouse","ss.input.sport2.multitap":true}' disc "$cue"; sat_firmware ss-ports
	nat ss-ports ss-ports --frames 1 --list-panel
	check "saturn:devices" "a 3D pad in port 1, a mouse in port 2 and a multitap in socket 2: the 3D pad's mode switch and the mouse's buttons are live, and port 7 is the last one with a pad" \
		sh -c "grep -q \"'P1 Mode Analog' active\" '$work/ss-ports.out' && grep -q \"'P2 Mouse Left' active\" '$work/ss-ports.out' && grep -q \"'P7 A' active\" '$work/ss-ports.out' && ! grep -q \"'P8 A' active\" '$work/ss-ports.out' && ! grep -q \"'P2 A' active\" '$work/ss-ports.out'"

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
	for t in runs pad sandbox controls bus lag state-every-frame state-other-box state-rewind setting devices lid disc-change chd chd-states chd-rewind save-data firmware-asked firmware-missing; do
		report "saturn:$t" SKIP "no Saturn game with its two BIOS files (SATURN_GAME, SATURN_BIOS_JP, SATURN_BIOS_NA_EU)"
	done
fi
report "pcfx" SKIP "the PC-FX has never been run: no game of it is at hand"
report "lynx" SKIP "the Lynx has never been run: no game of it is at hand"

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
print('saturn_jp.bin' if 'starts with the Japanese BIOS' in n else 'saturn_na_eu.bin')" "$work/ss.suggest")"
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
		check "engine:saturn-bus" "Chimera's RAM search reads the Saturn's bus: $(grep -o '2 live ranges, [0-9]* of [0-9]* bytes searched' "$work/ss.engine")" \
			grep -q "2 live ranges, 2097152 of 134217728 bytes searched, every candidate live and reading what the bus peeks" "$work/ss.engine"
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
else
	for t in vb saturn saturn-bus saturn-chd; do
		report "engine:$t" SKIP "set CHIMERA_ROOT to a Chimera checkout with build/meson-linux/chimera-run and this core's package (waterbox/build-package.sh -r <it>)"
	done
fi

printf '\n%d passed, %d failed, %d skipped\n' "$ok" "$failed" "$skipped"
[ "$ok" -gt 0 ] || { echo "NOTHING RAN"; exit 1; }
[ "$failed" -eq 0 ]
