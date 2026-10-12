#!/bin/sh
# Prints the Mednafen source files this core compiles, one a line, relative
# to extern/mednafen/src: the four systems (the Saturn, the Virtual Boy, the
# PC-FX, the Lynx), the processors and chips they use, the disc reader, and
# Mednafen's shared code. Mednafen's own programs (its window, its sound and
# input back ends, netplay, movies, cheats, its debugger) are not compiled:
# waterbox/ is this core's frontend.
#
# Mednafen's build generates a few tables with small programs (scu_dsp_gen,
# the 68000's gen): those generator sources are left out, their output is in
# the release archive.
#
# Usage: waterbox/list-sources.sh <extern/mednafen/src>
set -eu
cd "$1"
{
	# shared
	printf '%s\n' error.cpp VirtualFS.cpp FileStream.cpp MemoryStream.cpp Stream.cpp file.cpp \
		NativeVFS.cpp IPSPatcher.cpp git.cpp endian.cpp PSFLoader.cpp SSFLoader.cpp \
		resampler/resample.c
	find string hash compress video -name '*.cpp'
	find trio cputest zstd -name '*.c'
	# the decoders of a disc image's compressed sound tracks (Ogg Vorbis, Musepack)
	find tremor mpcdec -name '*.c'
	find sound -name '*.cpp' ! -name '*generate.cpp'
	# the disc reader: images of raw tracks (cue, ccd, toc), read on the
	# emulation thread
	printf 'cdrom/%s\n' CDAccess.cpp CDAccess_Image.cpp CDAccess_CCD.cpp CDAFReader.cpp CDAFReader_PCM.cpp \
		CDAFReader_Vorbis.cpp CDAFReader_MPC.cpp \
		CDInterface.cpp CDInterface_ST.cpp CDUtility.cpp scsicd.cpp lec.cpp recover-raw.cpp l-ec.cpp crc32.cpp galois.cpp
	# processors and chips
	find hw_cpu/m68k hw_cpu/v810 hw_video/huc6270 hw_sound/pce_psg -name '*.cpp' ! -name 'gen.cpp'
	# the systems
	find ss -name '*.cpp' ! -path '*/notes/*'
	find vb pcfx -name '*.cpp' ! -name 'debug.cpp' ! -path '*/notes/*'
	find lynx -name '*.cpp'
} | sort -u
