#!/bin/sh
# Writes a new patch from the edits made in extern/mednafen.
#
# extern/mednafen is Mednafen's archive with the patches in patches/ applied.
# Edit files there, build and test, then run this: it unpacks the archive
# again, applies the existing patches, and writes what differs from that in
# extern/mednafen as the next patch. The description is read from standard
# input and goes above the diff: what the change is, and why.
#
# Usage: waterbox/make-patch.sh <NNNN-what-it-does> < description.txt
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
name="${1:?usage: make-patch.sh <NNNN-what-it-does> < description.txt}"
out="$root/patches/$name.patch"
[ -e "$out" ] && { echo "$out exists" >&2; exit 1; }
archive="$(ls "$root"/build/cache/mednafen-*.tar.xz | head -1)"
tmp="$(mktemp -d "$root/build/cache/patch.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
tar -xJf "$archive" -C "$tmp"
mv "$tmp/mednafen" "$tmp/a"
for p in "$root"/patches/*.patch; do
	[ -f "$p" ] && patch -s -p1 -d "$tmp/a" < "$p"
done
ln -s "$root/extern/mednafen" "$tmp/b"
{
	cat
	echo
	# sources only: the build leaves nothing in extern/mednafen, and the
	# version stamp is not Mednafen's
	( cd "$tmp" && diff -ru -x .chimera-version a/src b/src | grep -v '^Only in\|^diff -ru' | sed -E 's/^(---|\+\+\+) ([^\t]*)\t.*$/\1 \2/' ) || true
} > "$out"
grep -q '^@@' "$out" || { rm -f "$out"; echo "nothing differs from the patched archive" >&2; exit 1; }
# the stamp, so that fetch-mednafen.sh sees the tree as up to date
sed -n '1p' "$root/extern/mednafen/.chimera-version" | cut -d' ' -f1,2 | { read v s; echo "$v $s $(cat "$root"/patches/*.patch | sha256sum | cut -d' ' -f1)" > "$root/extern/mednafen/.chimera-version"; }
echo "wrote patches/$name.patch ($(grep -c '^@@' "$out") hunks)"
