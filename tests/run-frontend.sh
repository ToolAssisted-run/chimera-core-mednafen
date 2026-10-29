#!/bin/bash
# The window test: the package loaded by Chimera itself (Chimera's
# window, run headless, with nobody at it), not by its headless
# runner. What is asked:
#  - the Virtual Boy program the tests assemble (tests/make-vb-program.py)
#    runs in the window as a project: the frames asked for, a picture of the
#    Virtual Boy's size, and the console's RAM byte for byte what Chimera's
#    headless runner leaves at the same frame;
#  - the keys the package ships become Chimera's keys for the pad;
#  - with a Saturn game and its BIOS files (SATURN_GAME, SATURN_BIOS_JP,
#    SATURN_BIOS_NA_EU, as waterbox/run-gate.sh takes them): the window asks
#    the core which BIOS the disc needs and takes it from Chimera's
#    firmware, and without that firmware it refuses the project and names
#    the file;
#  - with a PC-FX game and the console's BIOS (PCFX_GAME, PCFX_BIOS), with
#    a Lynx game and the console's boot ROM (LYNX_GAME, LYNX_BOOT) and with
#    an ST-V game and the board's BIOS set (STV_GAME, STV_BIOS): the
#    project opens with that file from Chimera's firmware and runs in the
#    window, with a picture of the machine's size.
#
# Usage: tests/run-frontend.sh --chimera-root <chimera checkout> [--frames N] [--keep]
#   --keep   leave the work folder (logs, configurations, projects) and say where it is
# Needs: Chimera built with its window (its tools/ci-chimera.sh), and the
# package installed in that checkout (waterbox/build-package.sh -r <chimera>).
set -u

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
wb="$root/waterbox"
frames=300
chimera_root=""
keep=""
while [ $# -gt 0 ]; do
	case "$1" in
		--keep) keep=1 ;;
		--chimera-root) chimera_root="$2"; shift ;;
		--frames) frames="$2"; shift ;;
		-*) echo "unknown option: $1" >&2; exit 2 ;;
		*) break ;;
	esac
	shift
done
[ -n "$chimera_root" ] && [ -d "$chimera_root" ] || { echo "say where Chimera is: --chimera-root <chimera checkout>" >&2; exit 2; }
chimera_root="$(cd "$chimera_root" && pwd)"
game="${SATURN_GAME:-$here/games-local/vfremix}"
bios_jp="${SATURN_BIOS_JP:-$here/roms-local/sega_101.bin}"
bios_na="${SATURN_BIOS_NA_EU:-$here/roms-local/mpr-17933.bin}"
fxgame="${PCFX_GAME:-$here/games-local/pcfx}"
fxbios="${PCFX_BIOS:-$here/roms-local/pcfx.rom}"
lxgame="${LYNX_GAME:-$here/games-local/lynx}"
lxboot="${LYNX_BOOT:-$here/roms-local/lynxboot.img}"
svgame="${STV_GAME:-$here/games-local/stv}"
svbios="${STV_BIOS:-$here/roms-local/stvbios.zip}"

chimera_exe="$chimera_root/build/meson-linux/source/ui/chimera"
package="$chimera_root/build/Cores/mednafen.chimeraCore"
runwbx="$root/build/meson-native/run-wbx"
core="$root/build/meson-guest/core.wbx"
runner="$chimera_root/build/meson-linux/chimera-run"
[ -x "$chimera_exe" ] || { echo "Chimera's window is not built: $chimera_exe" >&2; exit 1; }
[ -f "$package" ] || { echo "the package is not installed: $package (run waterbox/build-package.sh -r $chimera_root)" >&2; exit 1; }
[ -x "$runwbx" ] && [ -f "$core" ] || { echo "the sandbox build is not there: $runwbx, $core" >&2; exit 1; }
[ -x "$runner" ] || { echo "Chimera's headless runner is not built: $runner" >&2; exit 1; }

work="$(mktemp -d)"
cleanup() {
	if [ -n "$keep" ]; then echo "work folder kept: $work"; else rm -rf "$work"; fi
}
trap cleanup EXIT

# Chimera's window, run headless (it needs no display): the cores installed in
# the checkout, its settings, cache and recovery files the run's own, and
# nothing carried over from a Chimera installed on this machine
# the native test runner (run-wbx) needs miniBox's library, which Chimera's build holds
export LD_LIBRARY_PATH="$chimera_root/build/dll:$chimera_root/build:/usr/lib/x86_64-linux-gnu"
export ALSOFT_DRIVERS=null CHIMERA_CORES_DIR="$chimera_root/build/Cores" CHIMERA_QT_CACHE="$work/qt-cache" CHIMERA_QT_RECOVERY="$work/qt-recovery" \
	CHIMERA_QT_HASHES="$work/qt-file-hashes.txt" CHIMERA_QT_CHIMERA_SETTINGS="$work/no-chimera-config.ini"


ok=0
failed=0
skipped=0
report() {
	printf '%-16s %-5s %s\n' "$1" "$2" "$3"
	case "$2" in PASS) ok=$((ok + 1)) ;; SKIP) skipped=$((skipped + 1)) ;; *) failed=$((failed + 1)) ;; esac
}

# make_project <tag> <frames> <machine> <slot> <game file> [<firmware id>=<file>...]
# A project with the game beside it, where Chimera looks, and a movie of
# that many frames over the controls that are live for it.
make_project() {
	local tag="$1" nframes="$2" machine="$3" slot="$4" gamefile="$5"; shift 5
	local dir="$work/$tag" probe="$work/$tag.probe" fw=""
	mkdir -p "$dir" "$probe"
	for f in "$(dirname "$gamefile")"/*; do
		[ -f "$f" ] || continue
		[ -e "$dir/$(basename "$f")" ] || cp "$f" "$dir/"
		ln -sf "$f" "$probe/$(basename "$f")"
	done
	for f in "$@"; do ln -sf "${f#*=}" "$probe/${f%%=*}"; fw="$fw firmware=$f"; done
	printf '{"%s":["%s"],"savedata":[]}' "$slot" "$(basename "$gamefile")" > "$probe/slots"
	printf '{"machine":"%s"}' "$machine" > "$probe/settings"
	"$runwbx" "$core" "$probe" --frames 1 --list-panel > "$work/$tag.panel" 2> /dev/null
	rm -rf "$probe"
	# shellcheck disable=SC2086
	python3 "$here/make-project.py" "$package" "$dir/$tag.chimeraProject" "$nframes" "machine=$machine" "panel=$work/$tag.panel" $fw \
		-- "$slot=$dir/$(basename "$gamefile")" > "$work/$tag.log" 2>&1
}
# run_frontend <tag> <configuration> <frames> <domain or "">: the project in the window
run_frontend() {
	local tag="$1" cfg="$2" nframes="$3" domain="$4" job="$work/job.$1.txt"
	{
		echo "frames=$nframes"
		echo "out=$work/$tag.ram.bin"
		echo "meta=$work/$tag.meta.txt"
		echo "shot="
		echo "domain=$domain"
	} > "$job"
	( cd "$chimera_root" && MINIHAWK_JOB="$job" timeout -s KILL 900 "$chimera_exe" --headless \
		"--config=$cfg" "--project=$work/$tag/$tag.chimeraProject" "--lua=$here/${lua_script:-frontend-ram.lua}" ) >> "$work/$tag.log" 2>&1
	[ -f "$work/$tag.meta.txt" ] && grep -q "^status=OK" "$work/$tag.meta.txt"
}
value() { sed -n "s/^$2=//p" "$work/$1.meta.txt" 2>/dev/null; }

python3 "$here/settings-config.py" "$work/settings.base.json" '{}'

# ---- the Virtual Boy program: needs no file of anyone's
mkdir -p "$work/vbgame"
python3 "$here/make-vb-program.py" "$work/vbgame/chimera-test.vb"
# the movie is longer than the run: a window whose movie ends stops there
make_project vb $((frames + 100)) virtualboy cart "$work/vbgame/chimera-test.vb"
"$runner" --project "$work/vb/vb.chimeraProject" "$package" --files "$work/vb" --frames "$frames" \
	--dump "WRAM=$work/engine.ram.bin" > "$work/engine.log" 2>&1
if ! run_frontend vb "$work/settings.base.json" "$frames" WRAM; then
	report "window:vb" FAIL "Chimera did not finish the run: $(value vb detail) $(tail -2 "$work/vb.log" | tr '\n' ' ' | cut -c1-200)"
elif [ "$(value vb frames)" != "$frames" ] || [ "$(value vb width)" != 384 ] || [ "$(value vb height)" != 224 ]; then
	report "window:vb" FAIL "frames $(value vb frames) of $frames, picture $(value vb width)x$(value vb height) and not 384x224"
elif [ -s "$work/engine.ram.bin" ] && cmp -s "$work/engine.ram.bin" "$work/vb.ram.bin"; then
	report "window:vb" PASS "the Virtual Boy program ran $frames frames in Chimera's window, 384x224; its RAM ($(wc -c < "$work/vb.ram.bin") bytes, the program's counter at $(od -An -tu4 -N4 "$work/vb.ram.bin" | tr -d ' ')) is what the headless runner leaves"
else
	report "window:vb" FAIL "the RAM differs from the headless runner's (or one of the two is missing)"
fi

mkdir -p "$work/keys"; cp "$work/vb/chimera-test.vb" "$work/keys/"; sed 's/"mednafen-test-[^"]*"/"mednafen-test-keys"/' "$work/vb/vb.chimeraProject" > "$work/keys/keys.chimeraProject"
if lua_script=dump-controls.lua run_frontend keys "$work/settings.keys.json" 1 ""; then
	if python3 "$here/check-keybinds.py" "$work/keys.ram.bin" "$wb/default_keybinds.json" "Virtual Boy Controller" "P1 A" > "$work/keys.txt" 2>&1; then
		report "window:keys" PASS "$(cat "$work/keys.txt")"
	else
		report "window:keys" FAIL "$(head -1 "$work/keys.txt")"
	fi
else
	report "window:keys" FAIL "Chimera did not finish the run: $(tail -2 "$work/keys.log" | tr '\n' ' ' | cut -c1-200)"
fi

# ---- the Saturn, where there is a game and its BIOS
cue="$(ls "$game"/*.cue 2> /dev/null | head -1)"
if [ -z "$cue" ] || [ ! -f "$bios_jp" ] || [ ! -f "$bios_na" ]; then
	report "window:refusal" SKIP "needs a Saturn game (SATURN_GAME) and the two BIOS files"
	report "window:saturn" SKIP "needs a Saturn game (SATURN_GAME) and the two BIOS files"
else
	# which BIOS this disc starts with is the core's own answer
	probe="$work/ss.probe"; mkdir -p "$probe"
	for f in "$game"/*; do ln -sf "$f" "$probe/$(basename "$f")"; done
	printf '{"disc":["%s"],"savedata":[]}' "$(basename "$cue")" > "$probe/slots"; printf '{"machine":"saturn"}' > "$probe/settings"
	id="$("$runwbx" "$core" "$probe" --suggest 2> /dev/null | python3 -c "
import json, sys
t = sys.stdin.read()
print('saturn_jp.bin' if json.loads(t[t.index('{'):])['note'].startswith('suggest.japan') else 'saturn_na_eu.bin')")"
	rm -rf "$probe"
	[ "$id" = saturn_jp.bin ] && bios="$bios_jp" || bios="$bios_na"
	# the BIOS lives in a folder of its own, which Chimera is told of only by
	# the configuration of the run that is meant to find it
	fwdir="$(mktemp -d)"
	cp "$bios" "$fwdir/$(basename "$bios")"
	make_project ssnofw 100 saturn disc "$cue" "$id=$fwdir/$(basename "$bios")"
	if run_frontend ssnofw "$work/settings.base.json" 1 ""; then
		report "window:refusal" FAIL "the project opened without its BIOS"
	elif grep -q "$id" "$work/ssnofw.log"; then
		report "window:refusal" PASS "without the firmware the project is not opened, and $id is named: $(grep -o "[^.]*$id[^.]*" "$work/ssnofw.log" | head -1 | cut -c1-120)"
	else
		report "window:refusal" FAIL "refused, but the file is not named: $(tail -2 "$work/ssnofw.log" | tr '\n' ' ' | cut -c1-200)"
	fi
	python3 "$here/settings-config.py" "$work/settings.fw.json" '{}' "{\"$id\": \"$fwdir/$(basename "$bios")\"}"
	make_project ss $((frames + 100)) saturn disc "$cue" "$id=$fwdir/$(basename "$bios")"
	if ! run_frontend ss "$work/settings.fw.json" "$frames" ""; then
		report "window:saturn" FAIL "Chimera did not finish the run: $(value ss detail) $(tail -2 "$work/ss.log" | tr '\n' ' ' | cut -c1-200)"
	elif [ "$(value ss frames)" = "$frames" ] && [ "${value_w:=$(value ss width)}" -ge 320 ] 2> /dev/null; then
		report "window:saturn" PASS "a Saturn project opened with $id from Chimera's firmware and ran $frames frames in the window; its picture is $(value ss width)x$(value ss height)"
	else
		report "window:saturn" FAIL "frames $(value ss frames) of $frames, picture $(value ss width)x$(value ss height)"
	fi
	rm -rf "$fwdir"
fi

# ---- the PC-FX and the Lynx, where there is a game and the console's firmware
# window_machine <tag> <console's name> <machine> <slot> <game file> <firmware id> <firmware file> <least width> <least height>
window_machine() {
	local tag="$1" name="$2" machine="$3" slot="$4" gamefile="$5" id="$6" file="$7" w="$8" h="$9" fwdir
	fwdir="$(mktemp -d)"
	cp "$file" "$fwdir/$id"
	python3 "$here/settings-config.py" "$work/config.$tag.ini" '{}' "{\"$id\": \"$fwdir/$id\"}"
	make_project "$tag" $((frames + 100)) "$machine" "$slot" "$gamefile" "$id=$fwdir/$id"
	if ! run_frontend "$tag" "$work/config.$tag.ini" "$frames" ""; then
		report "window:$tag" FAIL "Chimera did not finish the run: $(value "$tag" detail) $(tail -2 "$work/$tag.log" | tr '\n' ' ' | cut -c1-200)"
	elif [ "$(value "$tag" frames)" = "$frames" ] && [ "$(value "$tag" width)" -ge "$w" ] 2> /dev/null && [ "$(value "$tag" height)" -ge "$h" ] 2> /dev/null; then
		report "window:$tag" PASS "a $name project opened with $id from Chimera's firmware and ran $frames frames in the window; its picture is $(value "$tag" width)x$(value "$tag" height)"
	else
		report "window:$tag" FAIL "frames $(value "$tag" frames) of $frames, picture $(value "$tag" width)x$(value "$tag" height)"
	fi
	rm -rf "$fwdir"
}
fxcue="$(ls "$fxgame"/*.cue 2> /dev/null | head -1)"
if [ -n "$fxcue" ] && [ -f "$fxbios" ]; then
	window_machine pcfx "PC-FX" pcfx disc "$fxcue" pcfx.rom "$fxbios" 256 224
else
	report "window:pcfx" SKIP "needs a PC-FX game (PCFX_GAME) and the console's BIOS (PCFX_BIOS)"
fi
lnx="$(ls "$lxgame"/*.lnx 2> /dev/null | head -1)"
if [ -n "$lnx" ] && [ -f "$lxboot" ]; then
	window_machine lynx "Lynx" lynx cart "$lnx" lynxboot.img "$lxboot" 160 102
else
	report "window:lynx" SKIP "needs a Lynx game (LYNX_GAME) and the console's boot ROM (LYNX_BOOT)"
fi
svzip="$(ls "$svgame"/*.zip 2> /dev/null | head -1)"
if [ -n "$svzip" ] && [ -f "$svbios" ]; then
	window_machine stv "Sega ST-V" stv romset "$svzip" stvbios.zip "$svbios" 320 224
else
	report "window:stv" SKIP "needs an ST-V game (STV_GAME) and the board's BIOS set (STV_BIOS)"
fi

echo
echo "$ok passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
