#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The pinned toolchain, built from source into .toolchain/.
#
#     tools/bootstrap.sh STEP...          (make bootstrap runs `all`)
#
#   cmake     CMake, built with the host's C++ compiler    -> .toolchain/cmake
#   ninja     Ninja, built with the pinned CMake            -> .toolchain/ninja
#   stage1    clang and lld, with the backends of both      -> .toolchain/stage1
#             targets, built with the host's C++ compiler;
#             they build the next three steps
#   libc      the system's C library, recorded: glibc on    -> .toolchain/sysroot
#             Linux, libSystem in the macOS SDK on Darwin;
#             the sysroot, empty, for GMP
#   runtimes  compiler-rt's builtins and the C++ runtimes   -> .toolchain/runtimes,
#             (libc++ and libc++abi; libunwind on Linux),      and beside stage 1
#             built with stage 1 for the target
#   stage2    LLVM, MLIR, clang, lld, clang-tidy and the    -> .toolchain/llvm
#             test tools, built with stage 1 against the
#             runtimes, which it installs beside itself
#   gmp       GMP (third_party/gmp), static, built with the -> .toolchain/sysroot
#             stage-2 clang
#   snmalloc  the runtime's allocator (third_party/snmalloc) -> .toolchain/snmalloc
#             at the lock's revision, with its patches: the
#             source the runtime's build compiles
#   simdutf   the runtime's UTF-8 kernels (third_party/      -> .toolchain/simdutf
#             simdutf) at the lock's revision, with its
#             patches: the source the runtime's build compiles
#   chez      Chez Scheme, threaded, with the host's C      -> .toolchain/chez
#             compiler: it runs Idris 2 and bench/'s baseline
#   idris     Idris 2 and its API (third_party/Idris2), on  -> .toolchain/idris2
#             the pinned Chez Scheme
#   typecheck LLVM and MLIR's TableGen and generated  -> .toolchain/typecheck
#             headers alone, built with the host's C++
#             compiler from stage 2's patched tree, and a
#             toolchain file for the host's compiler
#             against them (make typecheck); in no other
#             step, and not in `all`
#   llvm      stage1, libc, runtimes and stage2
#   all       every step but typecheck, in the order above
#
# Every host runs the same steps: one recipe builds the toolchain of either
# target. What the target's operating system forces is decided once, in the
# target section below, and nowhere else in this script.
#
# A step runs only when its provenance stamp is missing or stale. A stamp
# holds the digest of the step's inputs: the pinned revisions, the step's
# configuration, and the inputs of the steps it builds with, so a change to
# any of them makes the step, and every step built with it, stale. A step
# deletes its stamp first and writes it after everything, its checks
# included, succeeded. The long builds (stage1, stage2) resume in
# their build directory after a failure, when their inputs did not change.
#
# A bug in a pinned upstream is fixed by a patch to its source, kept with
# the bug's report as upstream/<bug>/<project>.patch (tools/patches.sh). The
# steps that build LLVM's compilers, runtimes and tools (stage1, runtimes,
# stage2), Chez Scheme and Idris 2, and the steps that export snmalloc and
# simdutf for the runtime, build a copy of the pinned source with their
# project's patches applied in name order, and fail naming the patch that
# does not apply. The patches are inputs of those steps and their stamps
# record them, so a changed or added patch rebuilds the step and everything
# built with it, and tools/verify-pins.sh refuses a tool built without it.
# Stage 1 builds the patched tree too: it compiles stage 2's LLVM, and what
# that code is compiled with is the patched driver's (stack clash
# protection on Darwin among it).
#
# Environment:
#   IDRIS_MLIR_TOOLCHAIN   the directory instead of .toolchain
#
# The builds run as many compile jobs as the one CPU budget allows
# (tools/host.sh: IDRIS_MLIR_NCPU, which the caller sets, else every
# core), and one link at a time, as LLVM's build advises for its links. ccache, on PATH or MacPorts',
# is the compiler launcher of every C and C++ compile, with
# its cache in .toolchain/ccache, capped at 1T: room for many pins and
# patch sets of LLVM, MLIR and clang.
#
# The host provides: a C and C++ compiler (cc and c++), make, git, python3
# (LLVM's configure), m4 (GMP), tar, coreutils (sha256sum, timeout, date),
# ccache, and curl to check release
# tarballs; the system's C library to build against: on Linux glibc's
# development files and the kernel's headers (Fedora's glibc-devel and
# kernel-headers), on Darwin the SDK of Xcode's command line tools. Each
# step logs
# to .toolchain/logs/STEP.log; a failure prints the log's end and exits 1, a
# usage error exits 2.

set -eu
LC_ALL=C
export LC_ALL
# Nothing of the caller's environment reaches the builds' flags or search
# paths.
unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS LIBS CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH \
  LIBRARY_PATH DESTDIR MAKEFLAGS MFLAGS MAKELEVEL CMAKE_PREFIX_PATH CMAKE_GENERATOR \
  CMAKE_TOOLCHAIN_FILE CMAKE_BUILD_TYPE CMAKE_INSTALL_PREFIX CLANG_NO_DEFAULT_CONFIG

root=$(cd "$(dirname "$0")/.." && pwd)
# Where the toolchain and its parts are (tools/toolchain.sh, which sources
# the host's tools where Linux and macOS differ: SHA-256, the memory).
. "$root/tools/toolchain.sh"
# The patches carried on the pinned upstreams.
. "$root/tools/patches.sh"
lock=$root/toolchain.lock.json
say() {
  printf '%s\n' "$*"
}

die() {
  printf 'bootstrap: error: %s\n' "$*" >&2
  exit 1
}

# The parts only the bootstrap names; the others (sysroot, llvm_prefix,
# snmalloc_prefix, simdutf_prefix, chez_prefix, idris_prefix,
# typecheck_toolchain, cmake)
# are tools/toolchain.sh's.
cmake_prefix=$toolchain/cmake
ninja_prefix=$toolchain/ninja
stage1=$toolchain/stage1
runtimes_prefix=$toolchain/runtimes
llvm_source=$toolchain/llvm-project
ninja=$ninja_prefix/bin/ninja
logs=$toolchain/logs
builds=$toolchain/build
host_cc=cc
host_cxx=c++
# Every LLVM this builds has the backends of both targets, whichever host
# builds it.
llvm_targets='AArch64;X86'

# --- The target ---------------------------------------------------------

# The toolchain compiles for the host's own target, one of the two this
# compiler has (AGENTS.md). The facts below are the ones the target's
# operating system forces, and the rest of the script reads them:
#
#   triple          the target programs are compiled for; CMakeLists.txt's
#                   target entry for it and the page size decides every
#                   fact of it the build needs
#   object_format   elf or macho: what an executable is, and what checks it
#   libc            the system's C library, which every program and tool
#                   links dynamically: glibc on Linux, libSystem on Darwin
#   libc_version    which the host has, which the libc step records, so
#                   that another makes the steps built against it stale
#   libc_flags      what the pinned clang's driver is told of it, on every
#                   compile and link (config_file)
#   cxx_libdir      where clang's driver finds the C++ runtimes beside it:
#                   the Linux driver searches lib/<triple>, the Darwin
#                   driver names no such directory, and the configuration
#                   file adds lib
#   builtins_dir    compiler-rt's directory of the builtins in the resource
#                   directory: the triple on Linux, darwin on Darwin
#   gmp_host        GMP's name for the target, and gmp_fat its run-time CPU
#                   dispatch, an x86 feature
#   stage2_disk     GiB a stage-2 build and install takes (measured on
#                   x86_64 Linux and arm64 Darwin)
host_kind=
case $(uname -s):$(uname -m) in
  Linux:x86_64 | Linux:aarch64) host_kind=linux ;;
  Darwin:arm64) host_kind=darwin ;;
  *) die "no target for a $(uname -s) $(uname -m) host: the targets are x86_64 and arm64 Linux and arm64 macOS" ;;
esac
# machine_fact SYSCTL GETCONF: a fact of the machine, from the kernel that
# decides it: sysctl's SYSCTL on Darwin, getconf's GETCONF on Linux, whose
# sysctl has no hw names. Neither stands in for the other: a sandbox that
# hides sysctl from this script must let it through, not get a guess.
machine_fact() {
  case $host_kind in
    darwin) machine_fact_out=$(sysctl -n "$1" 2> /dev/null) || machine_fact_out= ;;
    *) machine_fact_out=$(getconf "$2" 2> /dev/null) || machine_fact_out= ;;
  esac
  case $machine_fact_out in
    '' | *[!0-9]*) die "the host does not say its $1 (sysctl -n $1 on Darwin, getconf $2 on Linux)" ;;
  esac
  printf '%s\n' "$machine_fact_out"
}
# The page size, recorded in stage 2's recipe and stamp, named in the
# toolchain file, where CMakeLists.txt's target entry reads it, and checked
# at a program's entry: 16384 on Apple Silicon and the Raspberry Pi 5's
# Linux, 4096 on x86-64 and arm64 Linux's default kernel.
page_size=$(machine_fact hw.pagesize PAGESIZE) || exit 1
case $host_kind in
  linux)
    triple=$(uname -m)-unknown-linux-gnu
    object_format=elf
    libc=glibc
    libc_version=$(getconf GNU_LIBC_VERSION)
    # The pinned C++ runtimes and their unwinder, where the Linux driver's
    # defaults are GCC's.
    libc_flags='-stdlib=libc++
--unwindlib=libunwind'
    cxx_libdir=lib/$triple
    builtins_dir=$triple
    case $triple in
      x86_64-*) gmp_host=x86_64-pc-linux-gnu gmp_fat=--enable-fat ;;
      aarch64-*) gmp_host=aarch64-unknown-linux-gnu gmp_fat= ;;
    esac
    stage2_disk=13
    ;;
  darwin)
    triple=arm64-apple-macosx14.0
    object_format=macho
    libc=libSystem
    sdk=$(xcrun --show-sdk-path)
    libc_version="macOS SDK $(xcrun --show-sdk-version)"
    # The SDK, which upstream clang does not look for itself; and the pinned
    # libc++ beside the clang, which the Darwin driver names no directory
    # for, where -L makes -lc++ the static libc++.a, not the SDK's
    # libc++.tbd. Its headers the driver takes beside it, before the SDK's.
    libc_flags="-isysroot
$sdk
-L<CFGDIR>/../lib"
    cxx_libdir=lib
    builtins_dir=darwin
    gmp_host=aarch64-apple-darwin
    gmp_fat=
    stage2_disk=40
    ;;
esac
# native_cmake_flags: what a CMake build for this machine names beside its
# compilers: on Darwin, the architecture and the deployment target, which is
# the triple's.
native_cmake_flags() {
  case $object_format in
    macho) printf '%s\n' -DCMAKE_OSX_ARCHITECTURES=arm64 "-DCMAKE_OSX_DEPLOYMENT_TARGET=${triple##*macosx}" ;;
  esac
}

usage() {
  if [ $# -gt 0 ]; then printf 'bootstrap: %s\n' "$*" >&2; fi
  echo 'usage: tools/bootstrap.sh STEP...  (cmake ninja stage1 libc runtimes stage2 gmp snmalloc simdutf chez idris typecheck llvm all)' >&2
  exit 2
}

[ $# -gt 0 ] || usage
steps=
for arg in "$@"; do
  case $arg in
    cmake | ninja | stage1 | libc | runtimes | stage2 | gmp | snmalloc | simdutf | chez | idris | typecheck) steps="$steps $arg" ;;
    llvm) steps="$steps stage1 libc runtimes stage2" ;;
    all) steps="$steps cmake ninja stage1 libc runtimes stage2 gmp snmalloc simdutf chez idris" ;;
    -h | --help)
      sed -n '2,/^$/s/^# \{0,1\}//p' "$0"
      exit 0
      ;;
    *) usage "unknown step: $arg" ;;
  esac
done

jobs=$ncpu

# ccache, the compiler launcher of every C and C++ compile the steps run
# (CMake, Ninja, stage 1, the runtimes, stage 2, GMP, Chez): a rebuild
# after a patch, a pin move or a failed run
# recompiles only what changed. It is no input of any step, since it does
# not change what a step builds. The cache is .toolchain/ccache, and its
# settings are its own configuration file, which every run of ccache on it
# reads (ours, our CMake build's, `ccache -s`): a 1T cap; the times of
# headers ignored, since the patched llvm-project is written just before it
# is built; the defines a precompiled header was made with and the time
# macros not hashed, which is what lets ccache cache a compile that uses our
# build's precompiled header (made with -fno-pch-timestamp); and no build
# directory hashed, since a compile of the same unit
# in another directory, or another checkout, makes the same object (our
# build maps its paths away). What a user of the cache names is CCACHE_DIR
# and its own root, CCACHE_BASEDIR, under which paths are hashed relative
# to it, so the cache is shared by every checkout and names none.
ccache=$(host_path ccache) || die "no ccache on PATH or in /opt/local/bin (sudo port install ccache)"
CCACHE_DIR=$toolchain/ccache
CCACHE_BASEDIR=$root
export CCACHE_DIR CCACHE_BASEDIR
mkdir -p "$CCACHE_DIR"
printf '%s\n' 'max_size = 1T' 'sloppiness = include_file_ctime,include_file_mtime,pch_defines,time_macros' 'hash_dir = false' \
  > "$CCACHE_DIR/ccache.conf"
ccache_state="ccache $CCACHE_DIR"

# ccache_flags: the launcher, for a CMake configure. Like the job count, it
# is passed beside a step's recipe, not in it. ccache cannot cache a
# compile that uses a precompiled header made with a timestamp (LLVM's
# builds make them by default), so with ccache there are none: they only
# speed a compile up, and change nothing it produces.
ccache_flags() {
  printf '%s\n' "-DCMAKE_C_COMPILER_LAUNCHER=$ccache" "-DCMAKE_CXX_COMPILER_LAUNCHER=$ccache" \
    -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON
}

# ccache_cc VARIABLE COMPILER: the launcher, for a configure that names its
# compiler in a variable (VARIABLE=COMPILER, as the step's recipe gives
# it): the same assignment behind ccache, which, coming after the recipe's,
# is the one the configure keeps.
ccache_cc() {
  printf '%s\n' "$1=$ccache $2"
}
# lock_get TOOL KEY: a string of toolchain.lock.json (one field per line).
lock_get() {
  awk -v tool="$1" -v key="$2" '
    /^[ \t]*"[^"]*"[ \t]*:[ \t]*\{/ { split($0, part, "\""); object = part[2]; next }
    /^[ \t]*\}/ { object = ""; next }
    object == tool && match($0, "^[ \t]*\"" key "\"[ \t]*:[ \t]*\"") {
      value = substr($0, RLENGTH + 1); sub(/".*$/, "", value); print value; found = 1; exit
    }
    END { exit !found }' "$lock"
}

lock_value() {
  if ! lock_value_out=$(lock_get "$1" "$2") || [ -z "$lock_value_out" ]; then
    die "toolchain.lock.json has no $1.$2"
  fi
  printf '%s\n' "$lock_value_out"
}

# lock_name_key TOOL: the key that names TOOL's pinned revision for people:
# `tag` for a release, `describe` for a commit no tag names.
lock_name_key() {
  if lock_get "$1" tag > /dev/null; then
    echo tag
  elif lock_get "$1" describe > /dev/null; then
    echo describe
  else
    die "toolchain.lock.json has neither $1.tag nor $1.describe"
  fi
}

[ -f "$lock" ] || die "$lock is missing"
schema=$(sed -n 's/^[[:space:]]*"schema_version"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$lock")
[ "$schema" = 4 ] || die "toolchain.lock.json has schema ${schema:-none}; tools/bootstrap.sh reads schema 4"
llvm_revision=$(lock_value llvm revision) || exit 1
# LLVM is pinned to a commit of main, which has no tag: the lock names it
# by `git describe` instead.
llvm_name_key=$(lock_name_key llvm) || exit 1
llvm_name=$(lock_value llvm "$llvm_name_key") || exit 1
llvm_version=$(lock_value llvm version) || exit 1
llvm_major=${llvm_version%%.*}
# lld names its version without the `git` suffix a commit of main gives
# LLVM's (24.0.0git): `LLD 24.0.0 (<repository> <revision>)`.
lld_version=${llvm_version%git}
# The builtins compiler-rt installs for the target, under a clang's tree:
# on ELF the C runtime's start and end objects too, which clang links itself
# where libSystem has its own.
builtins=lib/clang/$llvm_major/lib/$builtins_dir
case $object_format in
  elf) builtins_files="$builtins/libclang_rt.builtins.a $builtins/clang_rt.crtbegin.o $builtins/clang_rt.crtend.o" ;;
  macho) builtins_files="$builtins/libclang_rt.osx.a" ;;
esac
cmake_revision=$(lock_value cmake revision) || exit 1
cmake_tag=$(lock_value cmake tag) || exit 1
cmake_version=$(lock_value cmake version) || exit 1
ninja_revision=$(lock_value ninja revision) || exit 1
ninja_tag=$(lock_value ninja tag) || exit 1
ninja_version=$(lock_value ninja version) || exit 1
gmp_revision=$(lock_value gmp revision) || exit 1
gmp_version=$(lock_value gmp version) || exit 1
snmalloc_revision=$(lock_value snmalloc revision) || exit 1
snmalloc_tag=$(lock_value snmalloc tag) || exit 1
simdutf_tag=$(lock_value simdutf tag) || exit 1
chez_revision=$(lock_value chez revision) || exit 1
chez_tag=$(lock_value chez tag) || exit 1
chez_version=$(lock_value chez version) || exit 1

# --- Stamps and inputs --------------------------------------------------

# stamp_get FILE KEY: a string field of a stamp (tools/toolchain.sh reads
# them the same way).
stamp_get() {
  sed -n "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$1" 2> /dev/null | head -n 1
}

# write_stamp FILE KEY VALUE...: the stamp, one string field per line,
# written whole or not at all.
write_stamp() {
  write_stamp_file=$1
  shift
  mkdir -p "$(dirname "$write_stamp_file")"
  {
    echo '{'
    while [ $# -ge 2 ]; do
      write_stamp_value=$(printf '%s' "$2" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')
      if [ $# -gt 2 ]; then write_stamp_comma=,; else write_stamp_comma=; fi
      printf '  "%s": "%s"%s\n' "$1" "$write_stamp_value" "$write_stamp_comma"
      shift 2
    done
    echo '}'
  } > "$write_stamp_file.new"
  mv "$write_stamp_file.new" "$write_stamp_file"
}

digest() {
  sha256 | cut -c1-64
}

stamp_of() {
  case $1 in
    cmake) echo "$cmake_prefix/provenance.json" ;;
    ninja) echo "$ninja_prefix/provenance.json" ;;
    stage1) echo "$stage1/provenance.json" ;;
    libc | gmp) echo "$sysroot/provenance/$1.json" ;;
    runtimes) echo "$runtimes_prefix/provenance.json" ;;
    stage2) echo "$llvm_prefix/provenance.json" ;;
    snmalloc) echo "$snmalloc_prefix/provenance.json" ;;
    simdutf) echo "$simdutf_prefix/provenance.json" ;;
    chez) echo "$chez_prefix/provenance.json" ;;
    idris) echo "$idris_prefix/provenance.json" ;;
    typecheck) echo "$typecheck_toolchain/provenance.json" ;;
    *) die "internal error: no step $1" ;;
  esac
}

# inputs STEP: the digest of the step's inputs, its recipe.
inputs() {
  inputs_text=$(recipe_"$1") || exit 1
  printf '%s\n' "$inputs_text" | digest
}

# current STEP: its stamp records its present inputs.
current() {
  current_stamp=$(stamp_of "$1")
  [ -f "$current_stamp" ] || return 1
  current_inputs=$(inputs "$1") || exit 1
  [ "$(stamp_get "$current_stamp" inputs)" = "$current_inputs" ]
}

# require STEP...: what this step builds with is built and current.
require() {
  for required in "$@"; do
    if ! current "$required"; then
      die "$step builds with $required, which is missing or stale; run: tools/bootstrap.sh $required"
    fi
  done
}

# quote_lines: each line of the input as one shell-quoted word, for
# `eval "set -- ..."`.
quote_lines() {
  sed "s/'/'\\\\''/g; s/^/'/; s/\$/'/" | tr '\n' ' '
}

# patch_inputs PROJECT: the project's patches as lines of a recipe, one per
# patch; none when it carries none, so that a recipe without patches is
# what it is without the mechanism.
patch_inputs() {
  patch_inputs_record=$(patch_record "$1") || die "cannot read upstream/*/$1.patch"
  [ -z "$patch_inputs_record" ] || printf '%s\n' "$patch_inputs_record" | sed 's/^/patch /'
}

# --- Running a step -----------------------------------------------------

# begin STEP WHAT: prints `up to date` and returns 1 when the step's stamp
# records its present inputs; otherwise deletes the stamp and opens the
# step's log. Sets step and step_inputs.
begin() {
  step=$1
  step_inputs=$(inputs "$1") || exit 1
  if [ -f "$(stamp_of "$1")" ] && [ "$(stamp_get "$(stamp_of "$1")" inputs)" = "$step_inputs" ]; then
    say "==> $1: up to date"
    summary="$summary
  $1: up to date"
    return 1
  fi
  rm -f "$(stamp_of "$1")"
  mkdir -p "$logs" "$builds"
  log=$logs/$1.log
  : > "$log"
  say "==> $1: $2"
  say "    log: $log"
  started=$(date +%s)
  return 0
}

# run WHAT CMD...: CMD, with its output in the step's log.
run() {
  run_what=$1
  shift
  say "    $run_what"
  printf '\n$ %s\n' "$*" >> "$log"
  if ! "$@" >> "$log" 2>&1; then
    tail -n 40 "$log" | sed 's/^/    | /' >&2
    die "$step: $run_what failed; the whole log is $log"
  fi
}

in_dir() {
  in_dir_path=$1
  shift
  (cd "$in_dir_path" && "$@")
}

need() {
  for need_tool in "$@"; do
    command -v "$need_tool" > /dev/null 2>&1 || die "$step needs $need_tool on PATH"
  done
}

# need_disk GIB WHAT
need_disk() {
  need_disk_kib=$(df -Pk "$toolchain" | awk 'NR == 2 { print $4 }')
  case $need_disk_kib in '' | *[!0-9]*) die "df cannot measure $toolchain" ;; esac
  if [ "$need_disk_kib" -lt $(($1 * 1048576)) ]; then
    die "$step needs about $1 GiB free under $toolchain for $2; $((need_disk_kib / 1048576)) GiB are free"
  fi
}

# build_dir [resume [KEY]]: the step's build directory, $build. With `resume`,
# one that a failed run left is kept when it was built from the same KEY: by
# default the step's inputs, or the digest of the part of them that the
# directory's long build reads.
build_dir() {
  build=$builds/$step
  build_key=${2:-$step_inputs}
  resumed=no
  if [ "${1-}" = resume ] && [ -f "$build/.inputs" ] && [ "$(cat "$build/.inputs")" = "$build_key" ]; then
    say "    resuming in $build"
    resumed=yes
  else
    rm -rf "$build"
    mkdir -p "$build"
    printf '%s\n' "$build_key" > "$build/.inputs"
  fi
}

size_mib() {
  du -sk "$1" 2> /dev/null | awk '{ print int($1 / 1024) }'
}

used_kib() {
  memory_used_kib 2> /dev/null || echo 0
}

# The most memory in use on the machine while a build runs,
# sampled every 5 seconds (there is no /usr/bin/time here), until the
# build stops or the bootstrap is gone (killed, it cannot stop it).
sampler=
sample_memory() {
  peak_file=$logs/$step.peak
  baseline_kib=$(used_kib)
  echo "$baseline_kib" > "$peak_file"
  sample_owner=$$
  (
    peak=0
    while alive "$sample_owner"; do
      now=$(used_kib)
      case $now in '' | *[!0-9]*) now=0 ;; esac
      if [ "$now" -gt "$peak" ]; then
        peak=$now
        echo "$peak" > "$peak_file"
      fi
      sleep 5
    done
  ) &
  sampler=$!
}

stop_sampling() {
  if [ -n "$sampler" ]; then
    kill "$sampler" 2> /dev/null || true
    wait "$sampler" 2> /dev/null || true
    sampler=
  fi
  peak_kib=$(cat "$peak_file" 2> /dev/null) || peak_kib=0
}

finish() {
  rm -rf "$build"
  finished
}

# finished: the step's time, in its output and the summary.
finished() {
  finish_seconds=$(($(date +%s) - started))
  finish_time=$(printf '%dh%02dm' $((finish_seconds / 3600)) $((finish_seconds % 3600 / 60)))
  say "    done in $finish_time"
  summary="$summary
  $step: built in $finish_time"
}

# version_is CMD TEXT: `CMD --version` says TEXT.
version_is() {
  version_out=$("$1" --version 2>&1) || die "$1 --version failed"
  case $version_out in
    *"$2"*) ;;
    *) die "$1 is not $2: $version_out" ;;
  esac
}

# glibc_pie READELF FILE: an ELF executable is position-independent (type
# DYN) and needs no shared library but glibc's own: the C library, its
# math library and the dynamic loader.
glibc_pie() {
  glibc_pie_out=$("$1" --file-header --dynamic "$2") || die "$1 cannot read $2"
  case $glibc_pie_out in *'Type:'*DYN*) ;; *) die "$2 is not position-independent" ;; esac
  glibc_pie_others=$(printf '%s\n' "$glibc_pie_out" | sed -n 's/.*(NEEDED).*\[\(.*\)\]$/\1/p' |
    grep -v -x -e 'libc\.so\.6' -e 'libm\.so\.6' -e 'ld-linux-.*\.so\.[0-9]*') || true
  [ -z "$glibc_pie_others" ] || die "$2 needs shared libraries that are not glibc's: $(echo $glibc_pie_others)"
}

# mh_pie OBJDUMP FILE: a Mach-O executable is position-independent when its
# header's flags name PIE (MH_PIE; llvm-objdump prints the flag as `PIE`).
# The target's programs are PIE executables linked against libSystem: no
# executable is static on Darwin.
mh_pie() {
  mh_pie_out=$("$1" --macho --private-headers "$2") || die "$1 cannot read $2"
  printf '%s\n' "$mh_pie_out" |
    awk '{ for (i = 1; i <= NF; i++) if ($i == "PIE") { found = 1 } } END { exit !found }' ||
    die "$2 is not position-independent (no PIE flag)"
}

# arm64_only OBJDUMP FILE: every Mach-O header in FILE, each slice of a
# universal file and each member of an archive, is arm64's: a Mach-O file
# can hold several architectures, and the toolchain's code is the target's
# alone.
arm64_only() {
  arm64_only_out=$("$1" --macho --arch=all --private-header "$2") || die "$1 cannot read $2"
  arm64_only_cpus=$(printf '%s\n' "$arm64_only_out" | awk '$1 ~ /^MH_(MAGIC|CIGAM)/ { print $2 }' | sort -u)
  [ "$arm64_only_cpus" = ARM64 ] || die "$2 is not arm64 alone (CPU types: $(echo $arm64_only_cpus))"
}

# check_executable PREFIX FILE: FILE is an executable as the target's
# programs are, read by PREFIX's tools: a PIE whose shared libraries are the
# system's C library and nothing else, never a libc++, since the pinned
# libc++ is static: on ELF glibc's alone; on Mach-O, of arm64 code alone,
# the operating system's own (/usr/lib, /System/Library).
check_executable() {
  case $object_format in
    elf) glibc_pie "$1/bin/llvm-readelf" "$2" ;;
    macho)
      mh_pie "$1/bin/llvm-objdump" "$2"
      arm64_only "$1/bin/llvm-objdump" "$2"
      check_executable_dylibs=$("$1/bin/llvm-objdump" --macho --dylibs-used "$2" |
        sed -n 's/^[[:space:]]*\([^ ]*\) (compatibility.*/\1/p' |
        grep -v -e '^/usr/lib/' -e '^/System/Library/' -e 'libc++') || true
      check_executable_cxx=$("$1/bin/llvm-objdump" --macho --dylibs-used "$2" | grep 'libc++') || true
      [ -z "$check_executable_dylibs$check_executable_cxx" ] ||
        die "$2 links shared libraries that are not the system's, or a shared libc++: $(echo $check_executable_dylibs $check_executable_cxx)"
      ;;
  esac
}

# check_native PREFIX FILE: an archive or object of the runtimes is the
# target's code alone. Only a Mach-O file can hold another architecture's.
check_native() {
  case $object_format in
    macho) arm64_only "$1/bin/llvm-objdump" "$2" ;;
  esac
}

# clone_pinned TOOL DEST: a shallow clone of the lock's revision,
# unmodified: by its tag when the lock names one, which must name that
# revision, else by the commit itself, fetched alone, whose `git describe`
# the lock records. A checkout of an earlier pin fetches the new one.
clone_pinned() {
  clone_repository=$(lock_value "$1" repository) || exit 1
  clone_revision=$(lock_value "$1" revision) || exit 1
  clone_key=$(lock_name_key "$1") || exit 1
  clone_name=$(lock_value "$1" "$clone_key") || exit 1
  if [ "$clone_key" = describe ]; then
    case $clone_revision in
      "${clone_name##*-g}"*) ;;
      *) die "toolchain.lock.json: $1's describe $clone_name does not name its revision $clone_revision" ;;
    esac
  fi
  if [ ! -e "$2/.git" ]; then
    rm -rf "$2"
    if [ "$clone_key" = tag ]; then
      run "clone $1 $clone_name" git clone --depth 1 --branch "$clone_name" "$clone_repository" "$2"
      clone_head=$(git -C "$2" rev-parse HEAD) || die "$2 is not a git checkout"
      [ "$clone_head" = "$clone_revision" ] ||
        die "$1's tag $clone_name is $clone_head; toolchain.lock.json pins $1 at $clone_revision"
    else
      run "init $1" git init -q "$2"
    fi
  fi
  if [ "$(git -C "$2" rev-parse HEAD 2> /dev/null)" != "$clone_revision" ]; then
    git -C "$2" cat-file -e "$clone_revision^{commit}" 2> /dev/null ||
      run "fetch $1 $clone_name" git -C "$2" fetch --depth 1 "$clone_repository" "$clone_revision"
    run "check out $1 $clone_name" git -C "$2" checkout -q --detach "$clone_revision"
  fi
  clone_head=$(git -C "$2" rev-parse HEAD) || die "$2 is not a git checkout"
  [ "$clone_head" = "$clone_revision" ] || die "$2 is at $clone_head; toolchain.lock.json pins $1 at $clone_revision"
  clone_changes=$(git -C "$2" status --porcelain --untracked-files=no) || die "git status failed in $2"
  [ -z "$clone_changes" ] || die "$2 has modifications; the pinned source must be unmodified"
}

# submodule PATH [TOOL]: PATH is checked out at its gitlink, unmodified, and
# the gitlink is the lock's revision of TOOL. Prints the gitlink.
submodule() {
  submodule_entry=$(git -C "$root" ls-files --stage -- "$1") || die "git ls-files failed"
  submodule_mode=$(printf '%s\n' "$submodule_entry" | awk '{ print $1 }')
  submodule_link=$(printf '%s\n' "$submodule_entry" | awk '{ print $2 }')
  [ "$submodule_mode" = 160000 ] || die "$1 is not a submodule"
  if [ $# -ge 2 ]; then
    submodule_pin=$(lock_value "$2" revision) || exit 1
    [ "$submodule_link" = "$submodule_pin" ] || die "$1: the gitlink is $submodule_link, but toolchain.lock.json pins $2 at $submodule_pin"
  fi
  [ -e "$root/$1/.git" ] || die "$1 is not checked out; run: git submodule update --init $1"
  submodule_head=$(git -C "$root/$1" rev-parse HEAD) || die "git rev-parse failed in $1"
  [ "$submodule_head" = "$submodule_link" ] || die "$1 is at $submodule_head, its gitlink at $submodule_link; run: git submodule update $1"
  submodule_changes=$(git -C "$root/$1" status --porcelain --untracked-files=no) || die "git status failed in $1"
  [ -z "$submodule_changes" ] || die "$1 has modifications"
  printf '%s\n' "$submodule_link"
}

# export_source CHECKOUT DEST [PROJECT]: the files of the checkout's commit,
# with one timestamp, so no generated file looks stale and the checkout is
# never written to; then PROJECT's patches, applied to them.
export_source() {
  rm -rf "$2"
  mkdir -p "$2"
  git -C "$1" archive --format=tar HEAD | tar -xf - -C "$2" || die "cannot export $1"
  [ -n "$(ls -A "$2")" ] || die "exporting $1 gave no files"
  if [ $# -ge 3 ]; then apply_patches "$3" "$2"; fi
}

# apply_patches PROJECT DIR: the project's patches, in the order they apply,
# to DIR, a fresh copy of its pinned source; a patch that does not apply
# fails the step and names the patch. Git reads DIR as the top of the tree:
# DIR may lie in another checkout (.toolchain is in this one), whose git
# would take the patch's paths from its own top and skip them unsaid.
apply_patches() {
  apply_patches_project=$1
  apply_patches_dir=$2
  apply_patches_list=$(patches "$1" | quote_lines) || die "cannot list upstream/*/$1.patch"
  eval "set -- $apply_patches_list"
  for apply_patches_file; do
    run "apply ${apply_patches_file#"$root"/}" in_dir "$apply_patches_dir" \
      env "GIT_CEILING_DIRECTORIES=${apply_patches_dir%/*}" git apply --verbose "$apply_patches_file"
  done
  if [ $# -gt 0 ]; then say "    $apply_patches_project: $# patches applied"; fi
}

# llvm_tree: the llvm-project stage 1, the runtimes and stage 2 build from,
# as $llvm_tree: the pinned checkout itself while no patch is carried;
# otherwise a copy of it with the patches applied, in .toolchain/build. The
# copy is kept, and reused, while the revision and the patches are the
# same, so that the three steps share it and a resumed build reads the
# files it was configured with, with the same timestamps.
llvm_tree() {
  clone_pinned llvm "$llvm_source"
  llvm_tree_patches=$(patch_inputs llvm) || exit 1
  if [ -z "$llvm_tree_patches" ]; then
    llvm_tree=$llvm_source
    return 0
  fi
  llvm_tree=$builds/llvm-project
  llvm_tree_key=$(printf 'llvm %s\n%s\n' "$llvm_revision" "$llvm_tree_patches" | digest)
  if [ -f "$llvm_tree.inputs" ] && [ "$(cat "$llvm_tree.inputs")" = "$llvm_tree_key" ]; then
    say "    patched llvm-project: $llvm_tree"
    return 0
  fi
  rm -f "$llvm_tree.inputs"
  say "    patched llvm-project: exporting $llvm_source to $llvm_tree"
  export_source "$llvm_source" "$llvm_tree" llvm
  printf '%s\n' "$llvm_tree_key" > "$llvm_tree.inputs"
}

# llvm_tree_done: stage 2, the last step to read the patched copy, has
# installed what it built from it. The typecheck step's build reads the
# copy in place, and is made again when it is gone.
llvm_tree_done() {
  rm -rf "$builds/llvm-project" "$builds/llvm-project.inputs"
}

# llvm_revision_flags: the revision LLVM's tools name in their version,
# the pin's, whichever tree they are built from: a patched copy is no
# checkout of its own, and lies inside this one.
llvm_revision_flags() {
  printf '%s\n' "-DLLVM_FORCE_VC_REVISION=$llvm_revision" \
    "-DLLVM_FORCE_VC_REPOSITORY=$(lock_value llvm repository)"
}

# verify_release TOOL PATH: the lock's release tarball, when it can be
# fetched, has the lock's SHA-256, and every file it ships is the pinned
# commit's, byte for byte (PINS.md: mirrored-sources). A release may ship
# fewer files than its repository (GMP's leaves out its development
# tests); those the commit has beyond the release are named in the check.
# Sets release_check.
verify_release() {
  release_url=$(lock_value "$1" release) || exit 1
  release_sha256=$(lock_value "$1" release_sha256) || exit 1
  release_dir=$builds/$1-release
  rm -rf "$release_dir"
  mkdir -p "$release_dir/files"
  if ! command -v curl > /dev/null 2>&1 ||
    ! curl -fsSL --max-time 300 -o "$release_dir/release" "$release_url" >> "$log" 2>&1; then
    release_check="not verified: $release_url could not be fetched"
    say "    release: $release_url could not be fetched; $1 rests on its pinned mirror commit (PINS.md: mirrored-sources)"
    rm -rf "$release_dir"
    return 0
  fi
  release_got=$(sha256 "$release_dir/release" | cut -c1-64)
  [ "$release_got" = "$release_sha256" ] ||
    die "$release_url has SHA-256 $release_got; toolchain.lock.json records $release_sha256"
  tar -xf "$release_dir/release" -C "$release_dir/files" || die "cannot unpack $release_url"
  release_top=$(ls "$release_dir/files")
  [ -d "$release_dir/files/$release_top" ] || die "$release_url does not unpack into one directory"
  release_tree=$(cd "$release_dir/files/$release_top" && git init -q && git add -A -f && git write-tree) ||
    die "git cannot hash the files of $release_url"
  release_want=$(git -C "$root/$2" rev-parse 'HEAD^{tree}') || die "git rev-parse failed in $2"
  if [ "$release_tree" = "$release_want" ]; then
    release_check="verified against $release_url"
  else
    # Each file as `<blob> TAB <path>`, the mode left out: a release's
    # tarball does not keep every executable bit its repository records.
    git -C "$release_dir/files/$release_top" ls-tree -r "$release_tree" | awk -F '\t' '{ split($1, f, " "); print f[3] "\t" $2 }' |
      sort > "$release_dir/shipped" || die "git cannot list the files of $release_url"
    git -C "$root/$2" ls-tree -r HEAD | awk -F '\t' '{ split($1, f, " "); print f[3] "\t" $2 }' |
      sort > "$release_dir/pinned" || die "git ls-tree failed in $2"
    release_differs=$(comm -23 "$release_dir/shipped" "$release_dir/pinned" | cut -f2 | head -n 5)
    [ -z "$release_differs" ] ||
      die "$release_url ships files that $2 lacks or holds otherwise: $(echo $release_differs)"
    release_extra=$(cut -f2 "$release_dir/shipped" | sort > "$release_dir/shipped.paths" &&
      cut -f2 "$release_dir/pinned" | sort | comm -23 - "$release_dir/shipped.paths") ||
      die "cannot compare the files of $release_url with $2"
    release_check="verified against $release_url, whose $(wc -l < "$release_dir/shipped" | tr -d ' ') files are $2's; $2 also has $(printf '%s\n' "$release_extra" | grep -c .) the release does not ship: $(echo $release_extra)"
  fi
  say "    release: $release_check"
  rm -rf "$release_dir"
}

# install_runtimes PREFIX: the runtimes' tree into a clang's, where its
# driver finds them beside it, replacing what an earlier install put there
# (its list is kept in the tree).
install_runtimes() {
  install_runtimes_list=$1/.runtimes.files
  if [ -f "$install_runtimes_list" ]; then
    while IFS= read -r install_runtimes_file; do rm -f "$1/$install_runtimes_file"; done < "$install_runtimes_list"
  fi
  (cd "$runtimes_prefix" && find . \( -type f -o -type l \) ! -name provenance.json | sed 's|^\./||' | sort) \
    > "$install_runtimes_list.new" || die "cannot list the runtimes in $runtimes_prefix"
  if [ -s "$install_runtimes_list.new" ]; then
    (cd "$runtimes_prefix" && tar -cf - -T "$install_runtimes_list.new") | (cd "$1" && tar -xf -) ||
      die "cannot install the runtimes into $1"
  fi
  mv "$install_runtimes_list.new" "$install_runtimes_list"
}

# install_staged NAME STAGE: STAGE's files into the sysroot, replacing what
# NAME installed before (its list is kept next to its stamp).
install_staged() {
  mkdir -p "$sysroot/provenance"
  install_list=$sysroot/provenance/$1.files
  if [ -f "$install_list" ]; then
    while IFS= read -r install_file; do rm -f "$sysroot/$install_file"; done < "$install_list"
  fi
  (cd "$2" && find . \( -type f -o -type l \) | sed 's|^\./||' | sort) > "$install_list.new"
  (cd "$2" && tar -cf - .) | (cd "$sysroot" && tar -xf -) || die "cannot copy $1 into $sysroot"
  mv "$install_list.new" "$install_list"
}

# --- Recipes ------------------------------------------------------------

# The only configuration of the pinned clangs, next to them, which clang
# reads for the triple it compiles for (<CFGDIR> is the file's directory).
# Every caller names the target (--target, CMAKE_<LANG>_COMPILER_TARGET):
# the Linux clang's default triple is the target's, but the Darwin clang's
# is the host's arm64-apple-darwin<kernel version>, never the triple LLVM
# was configured with, so a caller that did not name it would find no file.
# On every target: the system's C library and headers, linked dynamically
# (libc_flags); compiler-rt's builtins, the pinned libc++ and lld beside
# this clang, linked statically; GMP in the sysroot beside it, its headers
# system headers. Executables are PIE, both drivers' default.
config_file() {
  cat << CFG
# idris-mlir's toolchain for $triple, written by tools/bootstrap.sh:
# the system's C library ($libc_version), linked dynamically; the pinned
# libc++, compiler-rt and lld beside this clang, linked statically; GMP in
# the sysroot beside it.
--rtlib=compiler-rt
-fuse-ld=lld
$libc_flags
-isystem<CFGDIR>/../../sysroot/usr/include
-L<CFGDIR>/../../sysroot/usr/lib
CFG
}

# The CMake toolchain file of the pinned clang, which every configure preset
# names (CMakePresets.json): the compilers and the tools beside them, the
# target they compile for, the linker, and MLIR's package. Its paths are its
# own directory's, so the toolchain can move.
toolchain_file() {
  cat << CMAKE
# idris-mlir's pinned toolchain for $triple, written by tools/bootstrap.sh.
set(CMAKE_C_COMPILER "\${CMAKE_CURRENT_LIST_DIR}/bin/clang")
set(CMAKE_CXX_COMPILER "\${CMAKE_CURRENT_LIST_DIR}/bin/clang++")
set(CMAKE_C_COMPILER_TARGET "$triple")
set(CMAKE_CXX_COMPILER_TARGET "$triple")
set(CMAKE_LINKER_TYPE LLD)
set(CMAKE_AR "\${CMAKE_CURRENT_LIST_DIR}/bin/llvm-ar" CACHE FILEPATH "the pinned archiver")
set(CMAKE_RANLIB "\${CMAKE_CURRENT_LIST_DIR}/bin/llvm-ranlib" CACHE FILEPATH "the pinned ranlib")
set(CMAKE_NM "\${CMAKE_CURRENT_LIST_DIR}/bin/llvm-nm" CACHE FILEPATH "the pinned nm")
set(CMAKE_OBJDUMP "\${CMAKE_CURRENT_LIST_DIR}/bin/llvm-objdump" CACHE FILEPATH "the pinned objdump")
set(CMAKE_READELF "\${CMAKE_CURRENT_LIST_DIR}/bin/llvm-readelf" CACHE FILEPATH "the pinned readelf")
set(MLIR_DIR "\${CMAKE_CURRENT_LIST_DIR}/lib/cmake/mlir" CACHE PATH "the pinned MLIR's package")
set(IDRIS_MLIR_SNMALLOC "\${CMAKE_CURRENT_LIST_DIR}/../snmalloc/src" CACHE PATH "the runtime's snmalloc, with its patches")
set(IDRIS_MLIR_SIMDUTF "\${CMAKE_CURRENT_LIST_DIR}/../simdutf/src" CACHE PATH "the runtime's simdutf, with its patches")
set(IDRIS_MLIR_PAGE_SIZE $page_size CACHE STRING "the target's page size, the machine's that built this toolchain")
CMAKE
}

# The stage-1 tools, for everything stage 1 builds.
stage1_tools() {
  printf '%s\n' "-DCMAKE_MAKE_PROGRAM=$ninja" \
    "-DCMAKE_C_COMPILER=$stage1/bin/clang" "-DCMAKE_CXX_COMPILER=$stage1/bin/clang++" \
    "-DCMAKE_ASM_COMPILER=$stage1/bin/clang" "-DCMAKE_C_COMPILER_TARGET=$triple" \
    "-DCMAKE_CXX_COMPILER_TARGET=$triple" "-DCMAKE_ASM_COMPILER_TARGET=$triple" \
    "-DCMAKE_AR=$stage1/bin/llvm-ar" "-DCMAKE_RANLIB=$stage1/bin/llvm-ranlib" \
    "-DCMAKE_NM=$stage1/bin/llvm-nm"
}

# LLVM's optional host dependencies, all off: the tools depend on nothing
# of the host but its C library, the same on every target.
llvm_without_host_libraries() {
  printf '%s\n' -DLLVM_ENABLE_BINDINGS=OFF -DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LZMA=OFF -DLLVM_ENABLE_LIBPFM=OFF \
    -DLLVM_ENABLE_CURL=OFF -DLLVM_ENABLE_HTTPLIB=OFF -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_DOCS=OFF
}

args_cmake() {
  printf '%s\n' "--prefix=$cmake_prefix" -- -DCMAKE_USE_OPENSSL=OFF -DBUILD_TESTING=OFF
}

recipe_cmake() {
  printf '%s\n' "cmake $cmake_revision"
  args_cmake
}

args_ninja() {
  printf '%s\n' -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
    "-DCMAKE_C_COMPILER=$host_cc" "-DCMAKE_CXX_COMPILER=$host_cxx"
}

recipe_ninja() {
  printf '%s\n' "ninja $ninja_revision"
  args_ninja
}

# Only what the next steps use: the compilers, the linker, the archiver
# and nm, and the tools that read an executable (readelf for ELF, objdump
# for Mach-O).
stage1_components='clang;clang-resource-headers;lld;llvm-ar;llvm-ranlib;llvm-nm;llvm-objdump;llvm-readobj;llvm-readelf'

args_stage1() {
  printf '%s\n' -G Ninja -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_C_COMPILER=$host_cc" "-DCMAKE_CXX_COMPILER=$host_cxx" \
    "-DCMAKE_MAKE_PROGRAM=$ninja" "-DCMAKE_INSTALL_PREFIX=$stage1" \
    '-DLLVM_ENABLE_PROJECTS=clang;lld' "-DLLVM_TARGETS_TO_BUILD=$llvm_targets" \
    "-DLLVM_DEFAULT_TARGET_TRIPLE=$triple" -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF -DCLANG_PLUGIN_SUPPORT=OFF \
    "-DLLVM_DISTRIBUTION_COMPONENTS=$stage1_components"
  native_cmake_flags
  llvm_without_host_libraries
}

recipe_stage1() {
  printf '%s\n' "llvm $llvm_revision" "host compiler $("$host_cxx" --version 2>&1 | head -n 1)"
  patch_inputs llvm
  args_stage1
  config_file
}

recipe_libc() {
  printf '%s\n' "$libc $libc_version" "$libc_flags"
}

# compiler-rt's builtins, by stage 1, for the target, into the runtimes'
# resource directory. On Linux, one per-target directory with the C
# runtime's start and end objects; on Darwin, the osx library for arm64
# alone, since compiler-rt otherwise builds every architecture the SDK has.
args_builtins() {
  printf '%s\n' -G Ninja -DCMAKE_BUILD_TYPE=Release
  stage1_tools
  printf '%s\n' -DCMAKE_DISABLE_FIND_PACKAGE_LLVM=ON \
    "-DCOMPILER_RT_INSTALL_PATH=$runtimes_prefix/lib/clang/$llvm_major"
  native_cmake_flags
  case $object_format in
    elf)
      printf '%s\n' -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON -DCOMPILER_RT_BUILD_CRT=ON \
        -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON
      ;;
    macho)
      printf '%s\n' -DDARWIN_osx_BUILTIN_ARCHS=arm64 -DDARWIN_osx_SKIP_CC_KEXT=ON \
        -DCOMPILER_RT_ENABLE_IOS=OFF -DCOMPILER_RT_ENABLE_WATCHOS=OFF \
        -DCOMPILER_RT_ENABLE_TVOS=OFF -DCOMPILER_RT_ENABLE_XROS=OFF
      ;;
  esac
}

# The C++ runtimes, by stage 1, for the target, static, into the runtimes'
# tree as clang's driver expects them beside it (cxx_libdir). On glibc,
# LLVM's unwinder too; libSystem is Darwin's unwinder.
args_libcxx() {
  printf '%s\n' -G Ninja -DCMAKE_BUILD_TYPE=Release
  stage1_tools
  printf '%s\n' -DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON \
    -DCMAKE_ASM_COMPILER_WORKS=ON "-DCMAKE_INSTALL_PREFIX=$runtimes_prefix" \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_DOCS=OFF \
    -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXX_ENABLE_SHARED=OFF \
    -DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY=ON \
    -DLIBCXX_ENABLE_TIME_ZONE_DATABASE=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXX_INCLUDE_TESTS=OFF
  native_cmake_flags
  case $libc in
    glibc)
      printf '%s\n' '-DLLVM_ENABLE_RUNTIMES=libunwind;libcxxabi;libcxx' \
        -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
        -DLIBUNWIND_ENABLE_SHARED=OFF -DLIBUNWIND_USE_COMPILER_RT=ON \
        -DLIBCXXABI_USE_COMPILER_RT=ON -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
        -DLIBCXX_USE_COMPILER_RT=ON
      ;;
    # libSystem loads the system's libc++ into every process, and dyld
    # binds a weak definition to the first image that exports it: a
    # static libc++ that exported its symbols would have its locales and
    # streams bound to the system's, two implementations freeing each
    # other's memory. Built hermetic, it exports nothing.
    libSystem)
      printf '%s\n' '-DLLVM_ENABLE_RUNTIMES=libcxxabi;libcxx' \
        -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
        -DLIBCXX_HERMETIC_STATIC_LIBRARY=ON -DLIBCXXABI_HERMETIC_STATIC_LIBRARY=ON
      ;;
  esac
}

recipe_runtimes() {
  recipe_stage1_inputs=$(inputs stage1) || exit 1
  recipe_libc_inputs=$(inputs libc) || exit 1
  printf '%s\n' "llvm $llvm_revision"
  patch_inputs llvm
  printf '%s\n' "stage1 $recipe_stage1_inputs" "libc $recipe_libc_inputs"
  args_builtins
  args_libcxx
}

# What stage 2 installs.
stage2_components='clang;clang-scan-deps;clang-resource-headers;lld;clang-tidy;llvm-ar;llvm-ranlib;llvm-nm;llvm-objcopy;llvm-strip;llvm-objdump;llvm-readobj;llvm-readelf;llvm-symbolizer;opt;llc;FileCheck;not;count;mlir-opt;mlir-translate;mlir-tblgen;llvm-headers;llvm-libraries;cmake-exports;mlir-headers;mlir-libraries;mlir-cmake-exports'

# Stage 2, by stage 1, against the runtimes beside it, no assertions, no
# shared libraries or plugins, and no LTO: its libraries are native code,
# which every build of our tools links as it is, and a rebuild through the
# compiler cache relinks without optimizing LLVM again. One toolchain,
# without assertions, is the one our tools link and the tests run: no
# behaviour is chosen by the build. Statistics are forced on, so that
# llvm-config.h says they count to every includer, which an LLVM without
# assertions does not: a pass statistic's layout follows it. Its code takes
# stack clash protection, so that no frame larger than a page steps over a
# stack's guard: it is the frames of our tools that our compiler does not
# size. On every target a PIE linked against the system's C library.
args_stage2() {
  printf '%s\n' -G Ninja -DCMAKE_BUILD_TYPE=Release
  stage1_tools
  printf '%s\n' "-DCMAKE_INSTALL_PREFIX=$llvm_prefix" \
    '-DLLVM_ENABLE_PROJECTS=clang;lld;mlir;clang-tools-extra' "-DLLVM_TARGETS_TO_BUILD=$llvm_targets" \
    "-DLLVM_HOST_TRIPLE=$triple" "-DLLVM_DEFAULT_TARGET_TRIPLE=$triple" \
    -DLLVM_ENABLE_ASSERTIONS=OFF -DLLVM_FORCE_ENABLE_STATS=ON -DLLVM_ENABLE_RTTI=OFF -DLLVM_ENABLE_EH=OFF \
    -DLLVM_ENABLE_LIBCXX=ON -DLLVM_INSTALL_UTILS=ON \
    -DLLVM_ENABLE_LTO=OFF -DMLIR_INSTALL_AGGREGATE_OBJECTS=OFF -DLLVM_ENABLE_PLUGINS=OFF \
    -DCLANG_PLUGIN_SUPPORT=OFF "-DLLVM_DISTRIBUTION_COMPONENTS=$stage2_components"
  printf '%s\n' -DCMAKE_C_FLAGS=-fstack-clash-protection -DCMAKE_CXX_FLAGS=-fstack-clash-protection
  native_cmake_flags
  case $object_format in
    elf)
      printf '%s\n' "-DCMAKE_LINKER=$stage1/bin/ld.lld" -DLLVM_ENABLE_PIC=OFF
      ;;
    macho)
      printf '%s\n' "-DCMAKE_LINKER=$stage1/bin/ld64.lld" -DLLVM_ENABLE_PIC=ON -DLLVM_BUILD_STATIC=OFF
      ;;
  esac
  llvm_without_host_libraries
}

recipe_stage2() {
  recipe_stage1_inputs=$(inputs stage1) || exit 1
  recipe_libc_inputs=$(inputs libc) || exit 1
  recipe_runtimes_inputs=$(inputs runtimes) || exit 1
  printf '%s\n' "llvm $llvm_revision"
  patch_inputs llvm
  printf '%s\n' "stage1 $recipe_stage1_inputs" "libc $recipe_libc_inputs" \
    "runtimes $recipe_runtimes_inputs" "page $page_size"
  args_stage2
  config_file
  toolchain_file
}

# GMP, static and position-independent, by the stage-2 clang for the
# target: every x86-64 kernel selected at run time (gmp_fat), one arm64
# build, where there is no run-time dispatch to ask for. Its temporaries
# come from the allocator, never `alloca`, so no operand's size is a
# frame's (malloc-reentrant); its frames, which the compiler does not size,
# take stack clash protection.
args_gmp() {
  printf '%s\n' --prefix=/usr "--build=$gmp_host" "--host=$gmp_host"
  [ -z "$gmp_fat" ] || printf '%s\n' "$gmp_fat"
  printf '%s\n' --with-pic --disable-shared --enable-static --enable-alloca=malloc-reentrant \
    "CC=$llvm_prefix/bin/clang --target=$triple" "CFLAGS=-O2 -pipe -ffp-contract=off -fstack-clash-protection" \
    "AR=$llvm_prefix/bin/llvm-ar" "NM=$llvm_prefix/bin/llvm-nm" "RANLIB=$llvm_prefix/bin/llvm-ranlib"
}

recipe_gmp() {
  recipe_stage2_inputs=$(inputs stage2) || exit 1
  printf '%s\n' "gmp $gmp_revision" "stage2 $recipe_stage2_inputs"
  args_gmp
}

# snmalloc and simdutf are compiled by the runtime's build, each from its
# export: the submodule's commit, which is the lock's, with its patches
# applied.
recipe_export() {
  recipe_export_revision=$(submodule "third_party/$1" "$1") || exit 1
  printf '%s\n' "$1 $recipe_export_revision"
  patch_inputs "$1"
}

recipe_snmalloc() {
  recipe_export snmalloc
}

recipe_simdutf() {
  recipe_export simdutf
}

# chez_machine: Chez Scheme's threaded machine type for the host it runs on
# (it is a host program, like CMake, not a target).
chez_machine() {
  case $host_kind in
    linux) echo ta6le ;;
    darwin) echo tarm64osx ;;
  esac
}

# Chez's own configure, with its vendored zlib and LZ4. The REPL's editor
# (curses) and X11 are left out: Idris runs Chez only on programs. The
# install prefix is passed apart, so that a toolchain that links this one's
# Chez reads the same inputs.
args_chez() {
  args_chez_machine=$(chez_machine) || exit 1
  printf '%s\n' --threads "-m=$args_chez_machine" --disable-curses --disable-x11 --as-is "CC=$host_cc"
}

recipe_chez() {
  printf '%s\n' "chez $chez_revision"
  patch_inputs chez
  args_chez
}

# find_chez: the pinned Chez Scheme by its physical path, which every
# program Idris compiles names on its first line.
find_chez() {
  [ -x "$chez_prefix/bin/scheme" ] || die "no Chez Scheme in $chez_prefix; run: tools/bootstrap.sh chez"
  find_chez_bin=$(cd "$chez_prefix/bin" && pwd -P) || die "cannot resolve $chez_prefix/bin"
  printf '%s/scheme\n' "$find_chez_bin"
}

recipe_idris() {
  recipe_idris_revision=$(submodule third_party/Idris2) || exit 1
  recipe_chez_inputs=$(inputs chez) || exit 1
  printf '%s\n' "idris2 $recipe_idris_revision"
  patch_inputs idris
  printf '%s\n' "chez $recipe_chez_inputs" "make bootstrap install install-api"
}

# What the typecheck step builds: the TableGen tools and libraries, which
# idris-mlir-tblgen links, and every header LLVM and MLIR generate, which
# our code includes, directly or through MLIR's (LLVM's *_gen targets, three
# of them under llvm-headers; mlir-headers). Nothing else of LLVM is
# compiled, so nothing of ours can be linked but idris-mlir-tblgen.
typecheck_targets='llvm-tblgen mlir-tblgen MLIRTblgenLib llvm-headers acc_gen analysis_gen vt_gen mlir-headers'

# The typecheck build: stage 2's options that shape the headers our code
# includes (the triple, the targets, assertions and statistics, which
# llvm-config.h says to every includer; no RTTI or exceptions), with the
# host's compilers, which compile our code against it, and none of the
# host's optional libraries.
args_typecheck() {
  printf '%s\n' -G Ninja -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_C_COMPILER=$host_cc" "-DCMAKE_CXX_COMPILER=$host_cxx" "-DCMAKE_MAKE_PROGRAM=$ninja" \
    -DLLVM_ENABLE_PROJECTS=mlir "-DLLVM_TARGETS_TO_BUILD=$llvm_targets" \
    "-DLLVM_HOST_TRIPLE=$triple" "-DLLVM_DEFAULT_TARGET_TRIPLE=$triple" \
    -DLLVM_ENABLE_ASSERTIONS=OFF -DLLVM_FORCE_ENABLE_STATS=ON -DLLVM_ENABLE_RTTI=OFF -DLLVM_ENABLE_EH=OFF \
    -DLLVM_ENABLE_PLUGINS=OFF
  native_cmake_flags
  llvm_without_host_libraries
}

# The CMake toolchain file of the typecheck preset (CMakePresets.json): the
# host's compilers, by their paths, for the target's triple, MLIR's and
# LLVM's packages in the typecheck build tree, and IDRIS_MLIR_TYPECHECK,
# which makes the project a check that our code compiles
# (CMakeLists.txt). The project's C++26 is spelled for CMake, which does not
# know every host compiler's flag for it (Apple's clang); every compiler
# that has C++26 accepts -std=c++2c.
typecheck_toolchain_file() {
  typecheck_cc=$(command -v "$host_cc") || die "no $host_cc on PATH"
  typecheck_cxx=$(command -v "$host_cxx") || die "no $host_cxx on PATH"
  cat << CMAKE
# idris-mlir's typecheck toolchain for $triple, written by
# tools/bootstrap.sh typecheck: the host's compilers against the TableGen-only
# LLVM/MLIR build in $builds/typecheck-llvm.
set(CMAKE_C_COMPILER "$typecheck_cc")
set(CMAKE_CXX_COMPILER "$typecheck_cxx")
set(CMAKE_C_COMPILER_TARGET "$triple")
set(CMAKE_CXX_COMPILER_TARGET "$triple")
set(CMAKE_CXX26_STANDARD_COMPILE_OPTION "-std=c++2c")
set(CMAKE_CXX26_EXTENSION_COMPILE_OPTION "-std=gnu++2c")
set(MLIR_DIR "$builds/typecheck-llvm/lib/cmake/mlir" CACHE PATH "the TableGen-only MLIR's package")
set(LLVM_DIR "$builds/typecheck-llvm/lib/cmake/llvm" CACHE PATH "the TableGen-only LLVM's package")
set(IDRIS_MLIR_SNMALLOC "$snmalloc_prefix/src" CACHE PATH "the runtime's snmalloc, with its patches")
set(IDRIS_MLIR_SIMDUTF "$simdutf_prefix/src" CACHE PATH "the runtime's simdutf, with its patches")
set(IDRIS_MLIR_TYPECHECK ON CACHE BOOL "compile our code against the TableGen-only LLVM/MLIR" FORCE)
set(IDRIS_MLIR_PAGE_SIZE $page_size CACHE STRING "the target's page size, this machine's")
CMAKE
}

# What the typecheck build reads, apart from the targets it builds and the
# toolchain file written after it, so that another target or a change of
# the file alone resumes it.
typecheck_llvm_inputs() {
  printf '%s\n' "llvm $llvm_revision"
  patch_inputs llvm
  printf '%s\n' "host compiler $("$host_cxx" --version 2>&1 | head -n 1)"
  args_typecheck
}

recipe_typecheck() {
  typecheck_llvm_inputs
  printf '%s\n' "targets $typecheck_targets"
  typecheck_toolchain_file
}

# --- Steps --------------------------------------------------------------

step_cmake() {
  begin cmake "CMake $cmake_tag, with the host's C++ compiler" || return 0
  need git make "$host_cc" "$host_cxx"
  build_dir
  clone_pinned cmake "$build/src"
  eval "set -- $({ args_cmake; ccache_flags; } | quote_lines)"
  run configure in_dir "$build/src" env "CC=$host_cc" "CXX=$host_cxx" ./bootstrap "--parallel=$jobs" "$@"
  run build in_dir "$build/src" make -j "$jobs"
  rm -rf "$cmake_prefix"
  run install in_dir "$build/src" make install
  version_is "$cmake" "cmake version $cmake_version"
  write_stamp "$(stamp_of cmake)" step cmake revision "$cmake_revision" tag "$cmake_tag" \
    version "$cmake_version" inputs "$step_inputs" \
    host_compiler "$("$host_cxx" --version 2>&1 | head -n 1)" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish
}

step_ninja() {
  begin ninja "Ninja $ninja_tag, with the pinned CMake" || return 0
  require cmake
  need git make "$host_cc" "$host_cxx"
  build_dir
  clone_pinned ninja "$build/src"
  eval "set -- $({ args_ninja; ccache_flags; } | quote_lines)"
  run configure "$cmake" -S "$build/src" -B "$build/out" "$@"
  run build "$cmake" --build "$build/out" --parallel "$jobs"
  rm -rf "$ninja_prefix"
  mkdir -p "$ninja_prefix/bin"
  run install cp "$build/out/ninja" "$ninja"
  version_is "$ninja" "$ninja_version"
  write_stamp "$(stamp_of ninja)" step ninja revision "$ninja_revision" tag "$ninja_tag" \
    version "$ninja_version" inputs "$step_inputs" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish
}

# Stage 1, the host compiler's clang and lld from the patched tree; nothing
# else.
step_stage1() {
  begin stage1 "clang and lld $llvm_name, with the host's C++ compiler" || return 0
  require cmake ninja
  need git python3 "$host_cc" "$host_cxx"
  llvm_tree
  build_dir resume
  if [ "$resumed" = no ]; then need_disk 8 "the stage-1 build"; fi
  eval "set -- $({ args_stage1; llvm_revision_flags; ccache_flags; } | quote_lines)"
  sample_memory
  run configure "$cmake" -S "$llvm_tree/llvm" -B "$build" "$@" \
    "-DPython3_EXECUTABLE=$(command -v python3)" \
    "-DLLVM_PARALLEL_COMPILE_JOBS=$jobs" -DLLVM_PARALLEL_LINK_JOBS=1
  run "build (hours; progress in the log)" "$ninja" -C "$build" -j "$jobs" distribution
  build_mib=$(size_mib "$build")
  # The runtimes are installed into stage 1's tree, so they go with it.
  rm -rf "$stage1"
  rm -f "$(stamp_of runtimes)"
  run install "$ninja" -C "$build" install-distribution
  stop_sampling
  config_file > "$stage1/bin/$triple.cfg"
  version_is "$stage1/bin/clang" "clang version $llvm_version"
  version_is "$stage1/bin/ld.lld" "LLD $lld_version"
  [ "$("$stage1/bin/clang" "--target=$triple" -print-resource-dir)" = "$stage1/lib/clang/$llvm_major" ] ||
    die "stage 1's resource directory is not $stage1/lib/clang/$llvm_major"
  write_stamp "$(stamp_of stage1)" step stage1 revision "$llvm_revision" "$llvm_name_key" "$llvm_name" \
    version "$llvm_version" targets "$llvm_targets" inputs "$step_inputs" patches "$(patch_stamp llvm)" \
    host_compiler "$("$host_cxx" --version 2>&1 | head -n 1)" jobs "$jobs" compiler_cache "$ccache_state" \
    seconds "$(($(date +%s) - started))" peak_memory_mib "$((peak_kib / 1024))" \
    baseline_memory_mib "$((baseline_kib / 1024))" build_dir_mib "$build_mib" \
    install_mib "$(size_mib "$stage1")" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish
}

# The target's C library, the system's: the step records which the host
# has, so that another makes the steps built against it stale, and makes
# the sysroot that GMP goes into, empty, since what was in it was built
# against the C library before.
step_libc() {
  begin libc "$libc, the system's ($libc_version)" || return 0
  rm -rf "$sysroot"
  mkdir -p "$sysroot/usr/include" "$sysroot/usr/lib"
  build_dir
  write_stamp "$(stamp_of libc)" step libc libc "$libc" libc_version "$libc_version" \
    inputs "$step_inputs" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish
}

# The runtimes, with stage 1, for the target: compiler-rt's builtins and the
# C++ runtimes, installed into their own tree, .toolchain/runtimes, and from
# there beside stage 1, which builds stage 2 against them; stage 2 installs
# them beside itself.
step_runtimes() {
  begin runtimes "compiler-rt's builtins and the C++ runtimes for $triple, with stage 1" || return 0
  require stage1 libc
  need git python3
  llvm_tree
  build_dir
  # What an earlier run installed beside stage 1 goes first, so that nothing
  # is built against it.
  rm -rf "$runtimes_prefix"
  mkdir -p "$runtimes_prefix"
  install_runtimes "$stage1"
  eval "set -- $({ args_builtins; ccache_flags; } | quote_lines)"
  run "configure the builtins" "$cmake" -S "$llvm_tree/compiler-rt/lib/builtins" -B "$build/builtins" "$@"
  run "build the builtins" "$ninja" -C "$build/builtins" -j "$jobs"
  run "install the builtins" "$ninja" -C "$build/builtins" install
  # Stage 1's driver links the builtins from its own resource directory into
  # every program, the C++ runtimes' configure checks among them.
  install_runtimes "$stage1"
  eval "set -- $({ args_libcxx; ccache_flags; } | quote_lines)"
  run "configure the C++ runtimes" "$cmake" -S "$llvm_tree/runtimes" -B "$build/runtimes" "$@" \
    "-DPython3_EXECUTABLE=$(command -v python3)"
  run "build the C++ runtimes" "$ninja" -C "$build/runtimes" -j "$jobs"
  run "install the C++ runtimes" "$ninja" -C "$build/runtimes" install
  for runtimes_file in $builtins_files "$cxx_libdir/libc++.a" "$cxx_libdir/libc++abi.a" \
    include/c++/v1/vector; do
    [ -e "$runtimes_prefix/$runtimes_file" ] || die "the runtimes step installed no $runtimes_file"
  done
  for runtimes_file in $builtins_files "$cxx_libdir/libc++.a"; do
    check_native "$stage1" "$runtimes_prefix/$runtimes_file"
  done
  install_runtimes "$stage1"
  cat > "$build/check.cc" << 'CC'
#include <cstdio>
#include <string>
#include <vector>
int main() {
  std::vector<std::string> words{"libc++", "on", "the", "target"};
  std::string line;
  for (const auto &word : words) line += word + " ";
  try { throw 42; } catch (int) { std::printf("%sok\n", line.c_str()); return 0; }
  return 1;
}
CC
  run "check: a C++ program with exceptions, by stage 1" \
    "$stage1/bin/clang++" "--target=$triple" -std=c++20 -O2 "$build/check.cc" -o "$build/check"
  [ "$("$build/check")" = "libc++ on the target ok" ] || die "the C++ check program did not print its line"
  check_executable "$stage1" "$build/check"
  write_stamp "$(stamp_of runtimes)" step runtimes revision "$llvm_revision" "$llvm_name_key" "$llvm_name" \
    triple "$triple" inputs "$step_inputs" patches "$(patch_stamp llvm)" \
    compiler_cache "$ccache_state" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish
}

# Stage 2: LLVM, MLIR, clang, lld and clang-tidy, by stage 1, against the
# runtimes, into .toolchain/llvm, with the runtimes, the configuration file
# and the toolchain file beside them. The build makes the distribution's
# targets alone; then the objects are deleted, so that one copy of the
# libraries is on disk, and the install runs the commands of
# install-distribution without Ninja, which would rebuild the objects.
step_stage2() {
  begin stage2 "LLVM/MLIR, clang, lld and clang-tidy $llvm_name, with stage 1" || return 0
  require cmake ninja stage1 libc runtimes
  need git python3
  llvm_tree
  build_dir resume
  if [ "$resumed" = no ]; then need_disk "$stage2_disk" "the stage-2 build and install"; fi
  eval "set -- $({ args_stage2; llvm_revision_flags; ccache_flags; } | quote_lines)"
  sample_memory
  run configure "$cmake" -S "$llvm_tree/llvm" -B "$build" "$@" \
    "-DPython3_EXECUTABLE=$(command -v python3)" \
    "-DLLVM_PARALLEL_COMPILE_JOBS=$jobs" -DLLVM_PARALLEL_LINK_JOBS=1
  run "build (many hours; progress in the log)" "$ninja" -C "$build" -j "$jobs" distribution
  build_mib=$(size_mib "$build")
  rm -f "$build/.inputs"
  "$ninja" -C "$build" -t commands install-distribution | grep -e '-DCMAKE_INSTALL_COMPONENT=' > "$build/install.sh" ||
    die "stage 2 has no install commands"
  find "$build" -name '*.o' -type f -exec rm -f {} +
  rm -rf "$llvm_prefix"
  run install sh -e "$build/install.sh"
  stop_sampling
  install_runtimes "$llvm_prefix"
  config_file > "$llvm_prefix/bin/$triple.cfg"
  toolchain_file > "$llvm_prefix/toolchain.cmake"
  for stage2_file in bin/clang bin/clang++ bin/ld.lld bin/ld64.lld bin/clang-tidy bin/clang-scan-deps \
    bin/opt bin/llc bin/llvm-nm bin/llvm-ar bin/llvm-ranlib bin/llvm-readelf bin/llvm-objdump \
    bin/mlir-opt bin/mlir-translate bin/mlir-tblgen bin/FileCheck bin/not bin/count \
    lib/cmake/llvm/LLVMConfig.cmake lib/cmake/mlir/MLIRConfig.cmake lib/libLLVMSupport.a lib/libMLIRIR.a \
    include/mlir/IR/MLIRContext.h "lib/clang/$llvm_major/include/stddef.h" \
    $builtins_files "$cxx_libdir/libc++.a" include/c++/v1/vector "bin/$triple.cfg" toolchain.cmake; do
    [ -e "$llvm_prefix/$stage2_file" ] || die "stage 2 installed no $stage2_file"
  done
  version_is "$llvm_prefix/bin/clang" "clang version $llvm_version"
  version_is "$llvm_prefix/bin/ld.lld" "LLD $lld_version"
  version_is "$llvm_prefix/bin/mlir-opt" "LLVM version $llvm_version"
  version_is "$llvm_prefix/bin/FileCheck" "LLVM version $llvm_version"
  for stage2_file in bin/clang bin/mlir-opt; do
    check_executable "$llvm_prefix" "$llvm_prefix/$stage2_file"
  done
  for stage2_file in $builtins_files "$cxx_libdir/libc++.a"; do
    check_native "$llvm_prefix" "$llvm_prefix/$stage2_file"
  done
  mkdir -p "$build/check"
  printf '#include <stdio.h>\nint main(void) { puts("c ok"); return 0; }\n' > "$build/check/c.c"
  printf '#include <cstdio>\n#include <vector>\nint main() { std::vector<int> v{1, 2}; std::printf("c++ ok %%zu %%d\\n", v.size(), _LIBCPP_VERSION / 10000); }\n' > "$build/check/cc.cc"
  run "check: a C program" "$llvm_prefix/bin/clang" "--target=$triple" -O2 "$build/check/c.c" -o "$build/check/c"
  run "check: a C++26 program with the pinned libc++" "$llvm_prefix/bin/clang++" "--target=$triple" -std=c++26 -O2 \
    "$build/check/cc.cc" -o "$build/check/cc"
  [ "$("$build/check/c")" = "c ok" ] || die "the C check program did not print its line"
  [ "$("$build/check/cc")" = "c++ ok 2 $llvm_major" ] ||
    die "the C++ check program did not print its line with the pinned libc++'s version $llvm_major"
  for stage2_file in c cc; do
    check_executable "$llvm_prefix" "$build/check/$stage2_file"
  done
  write_stamp "$(stamp_of stage2)" step stage2 revision "$llvm_revision" llvm_revision "$llvm_revision" \
    "$llvm_name_key" "$llvm_name" version "$llvm_version" triple "$triple" targets "$llvm_targets" \
    libc "$libc" libc_version "$libc_version" page_size "$page_size" \
    inputs "$step_inputs" patches "$(patch_stamp llvm)" jobs "$jobs" compiler_cache "$ccache_state" \
    seconds "$(($(date +%s) - started))" peak_memory_mib "$((peak_kib / 1024))" \
    baseline_memory_mib "$((baseline_kib / 1024))" build_dir_mib "$build_mib" \
    install_mib "$(size_mib "$llvm_prefix")" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  llvm_tree_done
  finish
}

# GMP, with the stage-2 clang, into the sysroot.
step_gmp() {
  begin gmp "GMP $gmp_version, with the stage-2 clang, into the sysroot" || return 0
  require stage2 libc
  need git make m4
  submodule third_party/gmp gmp > /dev/null
  verify_release gmp third_party/gmp
  build_dir
  export_source "$root/third_party/gmp" "$build/src"
  mkdir -p "$build/out"
  eval "set -- $({ args_gmp; ccache_cc CC "$llvm_prefix/bin/clang --target=$triple"; } | quote_lines)"
  run configure in_dir "$build/out" "$build/src/configure" "$@"
  run build in_dir "$build/out" make -j "$jobs"
  run "check (GMP's tests)" in_dir "$build/out" make -j "$jobs" check
  run install in_dir "$build/out" make install "DESTDIR=$build/stage"
  rm -rf "$build/stage/usr/share" "$build/stage/usr/lib/libgmp.la"
  install_staged gmp "$build/stage"
  printf '#include <gmp.h>\n#include <stdio.h>\nint main(void) { mpz_t x; mpz_init(x); mpz_ui_pow_ui(x, 2, 100); gmp_printf("%%Zd\\n", x); mpz_clear(x); return 0; }\n' > "$build/check.c"
  run "check: a GMP program against the sysroot" \
    "$llvm_prefix/bin/clang" "--target=$triple" -O2 "$build/check.c" -o "$build/check" -lgmp
  [ "$("$build/check")" = 1267650600228229401496703205376 ] || die "the GMP check program did not print 2^100"
  check_executable "$llvm_prefix" "$build/check"
  write_stamp "$(stamp_of gmp)" step gmp revision "$gmp_revision" version "$gmp_version" \
    inputs "$step_inputs" release "$release_check" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish
}

# step_export PROJECT PREFIX TAG FILE: a library the runtime compiles,
# third_party/PROJECT at its gitlink, the lock's revision TAG, exported with
# its patches into PREFIX/src, which must hold FILE, and which the toolchain
# files name to the runtime's build (IDRIS_MLIR_SNMALLOC, IDRIS_MLIR_SIMDUTF).
# Nothing is compiled here: the runtime compiles it with its own profile.
step_export() {
  begin "$1" "$1 $3, with its patches, for the runtime" || return 0
  need git
  step_export_link=$(submodule "third_party/$1" "$1") || exit 1
  build_dir
  export_source "$root/third_party/$1" "$build/src" "$1"
  [ -f "$build/src/$4" ] || die "the export of third_party/$1 has no $4"
  rm -rf "$2"
  mkdir -p "$2"
  mv "$build/src" "$2/src"
  write_stamp "$(stamp_of "$1")" step "$1" revision "$step_export_link" tag "$3" \
    inputs "$step_inputs" patches "$(patch_stamp "$1")" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish
}

# The runtime's allocator.
step_snmalloc() {
  step_export snmalloc "$snmalloc_prefix" "$snmalloc_tag" src/snmalloc/snmalloc.h
}

# The runtime's UTF-8 kernels, whose implementation constructors are
# constexpr with its patches, so that the runtime holds the one the target's
# entry names as a constant of its own class.
step_simdutf() {
  step_export simdutf "$simdutf_prefix" "$simdutf_tag" include/simdutf/implementation.h
}

# Chez Scheme, with the host's C compiler. Idris 2 runs on it and bench/
# times Idris's Chez backend on it, so it is one pinned release on every
# host, not whichever the host packages. Idris's support library is
# loaded into its process. PIN(idris-support-host-cc) — see PINS.md
step_chez() {
  begin chez "Chez Scheme $chez_tag, with the host's C compiler" || return 0
  need git make "$host_cc"
  build_dir
  clone_pinned chez "$build/src"
  run "fetch zlib, LZ4, nanopass, stex and zuo (its submodules)" \
    git -C "$build/src" submodule update --init --depth 1
  chez_changes=$(git -C "$build/src" status --porcelain --untracked-files=no) || die "git status failed in $build/src"
  [ -z "$chez_changes" ] || die "$build/src or its submodules differ from the pinned commit's gitlinks"
  apply_patches chez "$build/src"
  eval "set -- $({ args_chez; ccache_cc CC "$host_cc"; } | quote_lines)"
  run configure in_dir "$build/src" ./configure "$@" "--installprefix=$chez_prefix"
  run build in_dir "$build/src" make -j "$jobs"
  rm -rf "$chez_prefix"
  run install in_dir "$build/src" make install
  version_is "$chez_prefix/bin/scheme" "$chez_version"
  chez_machine=$(chez_machine) || exit 1
  chez_says=$(echo '(display (list (machine-type) (threaded?)))' | "$chez_prefix/bin/scheme" -q) ||
    die "the installed scheme does not run"
  [ "$chez_says" = "($chez_machine #t)" ] || die "the installed scheme is $chez_says, not ($chez_machine #t)"
  write_stamp "$(stamp_of chez)" step chez revision "$chez_revision" tag "$chez_tag" \
    version "$chez_version" machine "$chez_machine" inputs "$step_inputs" \
    patches "$(patch_stamp chez)" host_compiler "$("$host_cc" --version 2>&1 | head -n 1)" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish
}

# Idris 2 on the pinned Chez Scheme. Its C support library is a shared
# object in the Chez process, a host program, so the host's C compiler
# builds it. PIN(idris-support-host-cc) — see PINS.md
# It is built in a copy of the checkout, with its patches applied, which is
# no checkout of its own: Idris's Makefile is told the version it would
# read from the checkout's git, nothing at a tagged release, else the
# commit's 9-character hash.
step_idris() {
  begin idris "Idris 2 and its API, on Chez Scheme $chez_tag" || return 0
  require chez
  need git make
  idris_revision=$(submodule third_party/Idris2) || exit 1
  chez=$(find_chez) || exit 1
  if git -C "$root/third_party/Idris2" describe --exact-match --tags > /dev/null 2>&1; then
    idris_version_tag=
  else
    idris_version_tag=$(git -C "$root/third_party/Idris2" rev-parse --short=9 HEAD) ||
      die "git rev-parse failed in third_party/Idris2"
  fi
  build_dir
  export_source "$root/third_party/Idris2" "$build/src" idris
  rm -rf "$idris_prefix"
  run bootstrap idris_make bootstrap
  run install idris_make install
  run "install the API" idris_make install-api "IDRIS2_BOOT=$idris_prefix/bin/idris2"
  "$idris_prefix/bin/idris2" --version > /dev/null 2>&1 || die "the installed idris2 does not run"
  write_stamp "$(stamp_of idris)" step idris idris2_revision "$idris_revision" scheme "$chez" \
    scheme_version "$("$chez" --version 2>&1 | head -n 1)" chez_revision "$chez_revision" \
    inputs "$step_inputs" patches "$(patch_stamp idris)" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish
}

# idris_make TARGET...: Idris 2's make, with no Idris environment of the
# caller's (upstream's bootstrap sets its own prefix for its first stage).
idris_make() {
  (
    unset IDRIS2_PATH IDRIS2_PACKAGE_PATH IDRIS2_INC_CGS IDRIS2_DATA IDRIS2_LIBS IDRIS2_CG \
      IDRIS2_BOOT IDRIS2_PREFIX
    CHEZ=$chez
    PATH=$idris_prefix/bin:$PATH
    export CHEZ PATH
    # Idris's C support library uses GMP, the sysroot's, built against the
    # system's C library, which the host's C compiler links too: through its
    # include and library directories (command-line variables, which reach
    # the sub-makes).
    cd "$build/src" && make "$@" "CPPFLAGS=-I$sysroot/usr/include" "LDFLAGS=-L$sysroot/usr/lib" \
      "PREFIX=$idris_prefix" "SCHEME=$chez" "VERSION_TAG=$idris_version_tag"
  )
}

# The typecheck build: what the host's C++ compiler needs to compile our
# code against the pinned LLVM/MLIR without stage 2, which takes hours: the
# patched tree's headers and the ones its TableGen generates, from a build
# of TableGen alone, and the toolchain file that names them. The build is
# kept, in .toolchain/build/typecheck-llvm, since the package it exports is
# that build tree, and so is the patched tree, which the package's include
# directories name (llvm_tree, without llvm_tree_done). Stage 2 deletes the
# patched tree once it has installed what it built from it; the step is
# then made again. The build resumes while what it reads is the same (a
# failed one too).
step_typecheck() {
  typecheck_stamp=$(stamp_of typecheck)
  if [ -f "$typecheck_stamp" ]; then
    typecheck_tree=$(stamp_get "$typecheck_stamp" tree)
    if [ -z "$typecheck_tree" ] || [ ! -f "$typecheck_tree/mlir/include/mlir/IR/OpBase.td" ]; then
      say "    typecheck: the tree its build reads is gone"
      rm -f "$typecheck_stamp"
    fi
  fi
  begin typecheck "LLVM/MLIR's TableGen and headers $llvm_name, with the host's C++ compiler" || return 0
  require cmake ninja snmalloc simdutf
  need git python3 "$host_cc" "$host_cxx"
  llvm_tree
  build=$builds/typecheck-llvm
  typecheck_key=$(typecheck_llvm_inputs | digest) || exit 1
  if [ -f "$build/.inputs" ] && [ "$(cat "$build/.inputs")" = "$typecheck_key" ]; then
    say "    resuming in $build"
  else
    rm -rf "$build"
    mkdir -p "$build"
    printf '%s\n' "$typecheck_key" > "$build/.inputs"
  fi
  eval "set -- $({ args_typecheck; llvm_revision_flags; ccache_flags; } | quote_lines)"
  run configure "$cmake" -S "$llvm_tree/llvm" -B "$build" "$@" \
    "-DPython3_EXECUTABLE=$(command -v python3)" \
    "-DLLVM_PARALLEL_COMPILE_JOBS=$jobs" -DLLVM_PARALLEL_LINK_JOBS=1
  # shellcheck disable=SC2086 # the targets are words
  run "build TableGen and the generated headers" "$ninja" -C "$build" -j "$jobs" $typecheck_targets
  for typecheck_file in bin/llvm-tblgen bin/mlir-tblgen lib/libMLIRTblgenLib.a lib/libMLIRTableGen.a \
    lib/libLLVMTableGen.a lib/libLLVMSupport.a lib/cmake/llvm/LLVMConfig.cmake \
    lib/cmake/mlir/MLIRConfig.cmake include/llvm/IR/IntrinsicEnums.inc include/llvm/Frontend/OpenMP/OMP.h.inc \
    tools/mlir/include/mlir/IR/BuiltinOps.h.inc; do
    [ -e "$build/$typecheck_file" ] || die "the typecheck build made no $typecheck_file"
  done
  version_is "$build/bin/mlir-tblgen" "LLVM version $llvm_version"
  mkdir -p "$typecheck_toolchain"
  typecheck_toolchain_file > "$typecheck_toolchain/toolchain.cmake.new" &&
    mv "$typecheck_toolchain/toolchain.cmake.new" "$typecheck_toolchain/toolchain.cmake" ||
    die "cannot write $typecheck_toolchain/toolchain.cmake"
  write_stamp "$(stamp_of typecheck)" step typecheck revision "$llvm_revision" llvm_revision "$llvm_revision" \
    "$llvm_name_key" "$llvm_name" version "$llvm_version" triple "$triple" targets "$llvm_targets" \
    inputs "$step_inputs" patches "$(patch_stamp llvm)" tree "$llvm_tree" llvm_build "$build" \
    toolchain_file "$typecheck_toolchain/toolchain.cmake" \
    host_compiler "$("$host_cxx" --version 2>&1 | head -n 1)" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finished
}

# --- Main ---------------------------------------------------------------

# alive PID: the process exists. A sandbox may refuse to signal a process
# it did not start; only "no such process" means it is gone.
alive() {
  alive_error=$(kill -0 "$1" 2>&1) && return 0
  case $alive_error in *'o such process'*) return 1 ;; esac
  return 0
}

# One bootstrap at a time, since two in one build directory build over each
# other. The lock is the kernel's (flock) on the toolchain directory,
# through descriptor 9, which every process of the run inherits: it is held
# while any of them lives, a killed bootstrap's orphaned ninja included,
# and released by the kernel when the last one exits. No file stands for
# it, so a run never finds a stale one and nobody can remove a live one.
# The holder file only names the process for the message.
mkdir -p "$toolchain"
holder=$toolchain/.bootstrap.holder
command -v python3 > /dev/null 2>&1 || die "tools/bootstrap.sh needs python3 on PATH (it takes the lock)"
exec 9< "$toolchain"
lock_status=0
python3 -c 'import fcntl, sys
try: fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError: sys.exit(3)' || lock_status=$?
case $lock_status in
  0) ;;
  3)
    lock_holder=$(cat "$holder" 2> /dev/null) || lock_holder=
    die "another tools/bootstrap.sh${lock_holder:+ (process $lock_holder)}, or a build it started, is running in $toolchain"
    ;;
  *) die "cannot lock $toolchain (python3's flock failed)" ;;
esac
echo $$ > "$holder"
cleanup() {
  if [ -n "$sampler" ]; then kill "$sampler" 2> /dev/null || true; fi
  rm -f "$holder"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

say "tools/bootstrap.sh:$steps ($jobs jobs; $triple; $ccache_state)"
summary=
for step in $steps; do
  "step_$step"
done
say "==> summary:$summary"
