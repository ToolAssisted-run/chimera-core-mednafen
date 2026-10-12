#!/bin/sh
# Gets Mednafen's source as this core builds it: the official release
# archive, checked against the checksum pinned here, unpacked into
# extern/mednafen, with the patches in patches/ applied.
#
# Mednafen is published as release archives only; it has no public
# repository to pin a commit of. So the pin is the archive's name and its
# SHA-256, and extern/mednafen is not in git (.gitignore).
#
# extern/mednafen is made again from the archive whenever the pin or a patch
# changes, so an edit made there by hand is lost: a change to Mednafen is a
# numbered patch in patches/ (docs/BUILDING.md says how to write one). The
# archive is kept in build/cache, so it is downloaded once.
#
# Usage: waterbox/fetch-mednafen.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
version="1.32.1"
url="https://mednafen.github.io/releases/files/mednafen-$version.tar.xz"
sha256="de7eb94ab66212ae7758376524368a8ab208234b33796625ca630547dbc83832"
dir="$root/extern/mednafen"
archive="$root/build/cache/mednafen-$version.tar.xz"

# what extern/mednafen has to be made of: the archive and every patch
want="$version $sha256 $(cat "$root"/patches/*.patch 2>/dev/null | sha256sum | cut -d' ' -f1)"
if [ -f "$dir/.chimera-version" ] && [ "$(cat "$dir/.chimera-version")" = "$want" ]; then
	exit 0
fi

sum_of() { sha256sum "$1" | cut -d' ' -f1; }
if [ ! -f "$archive" ] || [ "$(sum_of "$archive")" != "$sha256" ]; then
	mkdir -p "$root/build/cache"
	curl -sSL -o "$archive.part" "$url"
	got="$(sum_of "$archive.part")"
	[ "$got" = "$sha256" ] || { echo "the archive's checksum is $got, not the pinned $sha256" >&2; exit 1; }
	mv "$archive.part" "$archive"
fi

tmp="$(mktemp -d "$root/build/cache/unpack.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
tar -xJf "$archive" -C "$tmp"
for p in "$root"/patches/*.patch; do
	[ -f "$p" ] || continue
	patch -s -p1 -d "$tmp/mednafen" < "$p" || { echo "patch $(basename "$p") does not apply" >&2; exit 1; }
done
echo "$want" > "$tmp/mednafen/.chimera-version"
mkdir -p "$root/extern"
if [ -e "$dir" ]; then mv "$dir" "$tmp/old"; fi
mv "$tmp/mednafen" "$dir"
echo "extern/mednafen: Mednafen $version with $(ls "$root"/patches/*.patch 2>/dev/null | wc -l) patches"
