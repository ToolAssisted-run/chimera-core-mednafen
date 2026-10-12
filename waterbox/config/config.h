/* config.h for Mednafen as this core builds it.
 *
 * Mednafen's own build writes this file with a configure script that probes
 * the machine it runs on. This core is built twice - for the host (the
 * reference) and for miniBox's sandbox - and the two must be the same
 * program, so the answers are written down once, by hand, for the one
 * machine both are: x86-64, little-endian, a C library with the usual
 * string functions. Everything Mednafen's window, sound output, network play
 * and translations would need is left undefined: none of it is compiled.
 */
#pragma once

#define MEDNAFEN_VERSION "1.32.1"
#define MEDNAFEN_VERSION_NUMERIC 0x00103201
#define PACKAGE "mednafen"

/* the systems this core carries */
#define WANT_SS_EMU 1
#define WANT_VB_EMU 1
#define WANT_PCFX_EMU 1
#define WANT_LYNX_EMU 1

/* the machine */
#define ARCH_X86 1
#define ARCH_X86_64 1
#define LSB_FIRST 1
#define SIZEOF_CHAR 1
#define SIZEOF_SHORT 2
#define SIZEOF_INT 4
#define SIZEOF_LONG 8
#define SIZEOF_LONG_LONG 8
#define SIZEOF_OFF_T 8
#define SIZEOF_PTRDIFF_T 8
#define SIZEOF_SIZE_T 8
#define SIZEOF_VOID_P 8
#define SIZEOF_DOUBLE 8

/* path separators as POSIX has them */
#define MDFN_PSS_STYLE 1

/* AVX in inline assembly: Mednafen's configure finds it on any x86-64
 * compiler. It selects code in the sound resamplers only where the processor
 * says it has AVX, and this core does not use those resamplers. */
#define HAVE_INLINEASM_AVX 1

/* the Musepack decoder with integers, the same on every machine */
#define MPC_FIXED_POINT 1

/* the compiler and the C library */
#define STDC_HEADERS 1
#define HAVE_BUILTIN_EXPECT 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDDEF_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STRINGS_H 1
#define HAVE_LIMITS_H 1
#define HAVE_MEMORY_H 1
#define HAVE_UNISTD_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_FCNTL_H 1
#define HAVE_INTMAX_T 1
#define HAVE_UINTMAX_T 1
#define HAVE_LONG_LONG_INT 1
#define HAVE_UNSIGNED_LONG_LONG_INT 1
#define HAVE_WCHAR_T 1
#define HAVE_MEMCMP 1
#define HAVE_MEMCPY 1
#define HAVE_MEMMOVE 1
#define HAVE_MEMSET 1
#define HAVE_STRCASECMP 1
#define HAVE_STRDUP 1
#define HAVE_STRNLEN 1
#define HAVE_STRTOUL 1
#define HAVE_MKDIR 1
#define HAVE_GMTIME_R 1
#define ICONV_CONST

#ifndef _GNU_SOURCE
# define _GNU_SOURCE 1
#endif
