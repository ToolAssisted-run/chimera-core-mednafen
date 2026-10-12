#!/bin/sh
# Runs one game by hand: makes a work folder as the sandbox mounts a project
# (the game's files and the firmware under their names, as links to the
# copies under tests/), and runs the native reference on it.
#
# Usage: tests/try.sh [-g] <machine> <game folder under tests/games-local> [run options]
#   -g   the sandbox build and not the reference
# For a disc the folder's .cue or .chd is the disc; otherwise its one file is
# the game.
# SETTINGS in the environment adds settings to the project, and SAVES save
# data files (see below).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
flavor="native"
if [ "${1:-}" = "-g" ]; then flavor="guest"; shift; fi
machine="$1"; game="$2"; shift 2
work="$(mktemp -d "${TMPDIR:-/tmp}/mdfn-try.XXXXXX")"
for f in "$here/games-local/$game"/*; do
	[ -f "$f" ] && ln -s "$f" "$work/$(basename "$f")"
done
# the firmware, under the names the package mounts it by
for f in "$here/roms-local"/*; do
	[ -f "$f" ] || continue
	case "$(basename "$f")" in
		sega_101.bin|sega_100.bin|sega1003.bin) ln -sf "$f" "$work/saturn_jp.bin" ;;
		mpr-17933.bin|sega_100a.bin) ln -sf "$f" "$work/saturn_na_eu.bin" ;;
		*) ln -s "$f" "$work/$(basename "$f")" ;;
	esac
done
first="$(ls "$here/games-local/$game" | grep -i '\.cue$\|\.chd$' | head -1)"
if [ -n "$first" ]; then slot="disc"; else slot="cart"; first="$(ls "$here/games-local/$game" | head -1)"; fi
# SAVES lists save data files the project starts from: SAVES="/path/a.bkr /path/b.bcr"
saves=""
for f in ${SAVES:-}; do
	ln -s "$f" "$work/$(basename "$f")"
	saves="$saves${saves:+,}\"$(basename "$f")\""
done
printf '{"%s":["%s"]%s}' "$slot" "$first" "${saves:+,\"savedata\":[$saves]}" > "$work/slots"
# SETTINGS adds settings to the project: SETTINGS='"ss.input.port1":"3dpad","ss.h_overscan":false'
printf '{"machine":"%s"%s}' "$machine" "${SETTINGS:+,$SETTINGS}" > "$work/settings"
echo "work folder: $work" >&2
if [ "$flavor" = native ]; then
	"$root/build/meson-native/run-native" "$work" "$@"
else
	"$root/build/meson-native/run-wbx" "$root/build/meson-guest/core.wbx" "$work" "$@"
fi
