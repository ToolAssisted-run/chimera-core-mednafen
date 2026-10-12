# chimera-core-mednafen: Mednafen's Saturn, Virtual Boy, PC-FX and Lynx in
# miniBox's sandbox, as a Chimera core.
#
# Native reference build (run-native + run-wbx under the build directory):
#     sh waterbox/fetch-mednafen.sh
#     meson setup build/meson-native -Dminibox_dir=<miniBox> && ninja -C build/meson-native
# Guest (core.wbx) build via the cross file waterbox/setup-guest.sh writes
# (needs miniBox's C++ guest toolchain, build/meson-cpp):
#     sh waterbox/setup-guest.sh -m <miniBox> && ninja -C build/meson-guest core.wbx
#
# Mednafen builds with a configure script and makefiles that also build its
# window, its sound and input back ends and every system it has. None of that
# is used here: the source files of four systems and of what they need are
# compiled directly (waterbox/list-sources.sh names them), against a
# configuration header written by hand (waterbox/config/config.h), and
# waterbox/ is the program around them. Both flavours compile the SAME
# sources; only emulibc.h differs (waterbox/native-shim for the reference).
project('chimera-core-mednafen', ['c', 'cpp'],
  default_options: ['c_std=gnu99', 'cpp_std=gnu++14', 'optimization=2', 'debug=false', 'warning_level=0'])

md = 'extern/mednafen'

mb = get_option('minibox_dir')
if mb == ''
  mb_candidate = meson.current_source_dir() / '../chimera/extern/chimera-common-minibox'
  if import('fs').is_dir(mb_candidate)
    mb = mb_candidate
  else
    error('pass -Dminibox_dir=<miniBox checkout> (or keep one at ../chimera/extern/chimera-common-minibox)')
  endif
endif

defs = [
  '-DHAVE_CONFIG_H=1',
  '-DNDEBUG',
  # what the patches test for
  '-DCHIMERA_CORE',
  # Mednafen refuses, for speed, the code model the sandbox needs and warns
  # of position-independent code; both are what a core is built as
  '-DMDFN_DISABLE_NO_OPT_ERRWARN',
  '-DMDFN_DISABLE_PICPIE_ERRWARN',
]
# Mednafen's own code generation choices (its configure.ac): signed overflow
# wraps, no type-based aliasing, char is signed, and floating point is exactly
# what the source says - on every machine, in both flavours
flags = [
  '-fwrapv',
  '-fno-strict-aliasing',
  '-fsigned-char',
  '-fno-fast-math',
  '-fno-unsafe-math-optimizations',
  '-ffp-contract=off',
  '-fjump-tables',
  '-fomit-frame-pointer',
]
add_project_arguments(defs + flags, language: ['c', 'cpp'])

# Mednafen's headers are reached as <mednafen/...> through its include/
# folder, as in its own build. Its src/ folder is NOT on the path: it holds an
# endian.h that would take the place of the C library's. waterbox/config has
# config.h and the links configure would make to the bundled trio, minilzo
# and zstd headers.
inc = include_directories(
  'waterbox/config',
  'waterbox',
  md / 'include',
  'extern/zlib',
)

# zlib, pinned as a submodule: Mednafen bundles none and the sandbox's
# toolchain has none, and both flavours are to read a compressed file with
# the same code
zlib_names = ['adler32', 'compress', 'crc32', 'deflate', 'gzclose', 'gzlib', 'gzread', 'gzwrite',
  'infback', 'inffast', 'inflate', 'inftrees', 'trees', 'uncompr', 'zutil']
zlib_sources = []
foreach n : zlib_names
  zlib_sources += files('extern/zlib' / n + '.c')
endforeach
zlib = static_library('z', zlib_sources, c_args: ['-DHAVE_UNISTD_H', '-w'], pic: false)

listed = run_command(files('waterbox/list-sources.sh'), meson.current_source_dir() / md / 'src', check: true).stdout().strip().split('\n')
core_sources = []
foreach f : listed
  core_sources += files(md / 'src' / f)
endforeach
core_sources += files('waterbox/mdfn-interfaces.cpp', 'waterbox/cinterface.cpp')

if meson.is_cross_build()
  # ---- the guest: core.wbx --------------------------------------------------
  mbdir = meson.get_external_property('minibox_dir')
  mbuild = meson.get_external_property('minibox_build')
  sr = meson.get_external_property('guest_sysroot')

  executable('core', core_sources + files('waterbox/guest-syscalls.cpp'),
    name_suffix: 'wbx',
    link_with: zlib,
    include_directories: inc,
    link_args: [
      '-static', '-no-pie',
      '-Wl,--eh-frame-hdr', '-Wl,-O2', '-Wl,--no-relax', '-Wl,-z,stack-size=8388608',
      '-T', mbdir / 'source/guest/linkscript.T',
      '-Wl,-u,pthread_once', '-Wl,-u,pthread_cond_wait',
      '-Wl,-u,pthread_cond_broadcast', '-Wl,-u,pthread_key_create',
      '-Wl,-u,pthread_mutexattr_init', '-Wl,-u,pthread_mutexattr_settype',
      '-Wl,-u,pthread_mutexattr_destroy',
      mbuild / 'source/guest/cxxglue.c.o',
      mbuild / 'source/guest/emulibc.c.o',
      '-L' + sr / 'lib', '-lstdc++', '-lgcc', '-lgcc_eh', '-lc'])
else
  # ---- the native reference -------------------------------------------------
  m = meson.get_compiler('c').find_library('m', required: false)
  threads = dependency('threads')
  executable('run-native', core_sources + files('waterbox/run-native.c'),
    include_directories: [include_directories('waterbox/native-shim'), inc],
    c_args: ['-I' + mb / 'source/guest/include', '-I' + mb / 'extern/jsmn'],
    cpp_args: ['-I' + mb / 'source/guest/include', '-I' + mb / 'extern/jsmn'],
    link_with: zlib,
    dependencies: [m, threads])

  mbhost = mb / 'build/meson-linux/source/host'
  executable('run-wbx', files('waterbox/run-wbx.c'),
    c_args: ['-I' + mb / 'source/host'],
    link_args: [mbhost / 'libminiboxhost.so'],
    build_rpath: mbhost)
endif
