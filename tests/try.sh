#!/bin/sh
# Runs one game by hand: makes a work folder as the sandbox mounts a project
# (the game's files and the firmware under their names, as links to the
# copies under tests/), and runs the native reference on it.
#
# Usage: tests/try.sh [-g] <machine> <game folder under tests/games-local> [run options]
#   -g   the sandbox build and not the reference
# For a disc the folder's .cue is the disc; otherwise its one file is the game.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
flavor="native"
if [ "${1:-}" = "-g" ]; then flavor="guest"; shift; fi
machine="$1"; game="$2"; shift 2
work="$(mktemp -d "${TMPDIR:-/tmp}/mdfn-try.XXXXXX")"
for f in "$here/games-local/$game"/* "$here/roms-local"/*; do
	[ -f "$f" ] && ln -s "$f" "$work/$(basename "$f")"
done
first="$(ls "$here/games-local/$game" | grep -i '\.cue$' | head -1)"
if [ -n "$first" ]; then slot="disc"; else slot="cart"; first="$(ls "$here/games-local/$game" | head -1)"; fi
printf '{"%s":["%s"]}' "$slot" "$first" > "$work/slots"
printf '{"machine":"%s"}' "$machine" > "$work/settings"
echo "work folder: $work" >&2
if [ "$flavor" = native ]; then
	"$root/build/meson-native/run-native" "$work" "$@"
else
	"$root/build/meson-native/run-wbx" "$root/build/meson-guest/core.wbx" "$work" "$@"
fi
