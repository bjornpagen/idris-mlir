#!/bin/sh
# The pinned toolchain, built from source into .toolchain/.
#
#     tools/bootstrap.sh STEP...          (make bootstrap runs `all`)
#
#   cmake     CMake, built with the host's C++ compiler    -> .toolchain/cmake
#   ninja     Ninja, built with the pinned CMake            -> .toolchain/ninja
#   stage1    clang and lld for x86-64, built with the      -> .toolchain/stage1
#             host's C++ compiler; they build the next three steps
#   musl      musl (third_party/musl) and the host's Linux  -> .toolchain/sysroot
#             UAPI headers
#   runtimes  compiler-rt's builtins, libunwind, libc++abi  -> .toolchain/sysroot and
#             and libc++ for x86_64-unknown-linux-musl         stage 1's resource directory
#   stage2    LLVM, MLIR, clang, lld, clang-tidy and the    -> .toolchain/llvm-musl
#             test tools: static on musl and libc++, with LTO
#   gmp       GMP (third_party/gmp), static, built with the -> .toolchain/sysroot
#             stage-2 clang
#   idris     Idris 2 and its API (third_party/Idris2), on  -> .toolchain/idris2
#             the host's Chez Scheme
#   llvm      stage1, musl, runtimes and stage2
#   all       every step, in the order above
#
# A step runs only when its provenance stamp is missing or stale. A stamp
# holds the digest of the step's inputs: the pinned revisions, the step's
# configuration, and the inputs of the steps it builds with, so a change to
# any of them makes the step, and every step built with it, stale. A step
# deletes its stamp first and writes it after everything, its checks
# included, succeeded. The long builds (stage1, stage2) resume in
# their build directory after a failure, when their inputs did not change.
#
# Environment:
#   IDRIS_MLIR_TOOLCHAIN   the directory instead of .toolchain
#   IDRIS_MLIR_JOBS        parallel compile jobs (default: the cores, at most
#                          one per 5 GiB of memory); one link at a time
#   IDRIS_MLIR_STAGE2_LTO  Thin (default) or Full (PINS.md: stage2-thinlto)
#   CC, CXX                the host's C and C++ compilers (default: cc, c++)
#   CHEZ                   the Chez Scheme for Idris (default: chezscheme,
#                          scheme or chez on PATH)
#
# The host provides: a C and C++ compiler, make, git, python3
# (LLVM's configure), m4 (GMP), Chez Scheme (Idris), its Linux UAPI headers,
# tar, sha256sum, and curl to check release tarballs. Each step logs to
# .toolchain/logs/STEP.log; a failure prints the log's end and exits 1, a
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
toolchain=${IDRIS_MLIR_TOOLCHAIN:-$root/.toolchain}
lock=$root/toolchain.lock.json
triple=x86_64-unknown-linux-musl
cmake_prefix=$toolchain/cmake
ninja_prefix=$toolchain/ninja
stage1=$toolchain/stage1
sysroot=$toolchain/sysroot
llvm_musl=$toolchain/llvm-musl
idris_prefix=$toolchain/idris2
llvm_source=$toolchain/llvm-project
cmake=$cmake_prefix/bin/cmake
ninja=$ninja_prefix/bin/ninja
logs=$toolchain/logs
builds=$toolchain/build
host_cc=${CC:-cc}
host_cxx=${CXX:-c++}

say() {
  printf '%s\n' "$*"
}

die() {
  printf 'bootstrap: error: %s\n' "$*" >&2
  exit 1
}

usage() {
  if [ $# -gt 0 ]; then printf 'bootstrap: %s\n' "$*" >&2; fi
  echo 'usage: tools/bootstrap.sh STEP...  (cmake ninja stage1 musl runtimes stage2 gmp idris llvm all)' >&2
  exit 2
}

[ $# -gt 0 ] || usage
steps=
for arg in "$@"; do
  case $arg in
    cmake | ninja | stage1 | musl | runtimes | stage2 | gmp | idris) steps="$steps $arg" ;;
    llvm) steps="$steps stage1 musl runtimes stage2" ;;
    all) steps="$steps cmake ninja stage1 musl runtimes stage2 gmp idris" ;;
    gcc) usage "gcc is retired: the pinned C compiler is the stage-2 clang; run: tools/bootstrap.sh llvm" ;;
    -h | --help)
      sed -n '2,/^$/s/^# \{0,1\}//p' "$0"
      exit 0
      ;;
    *) usage "unknown step: $arg" ;;
  esac
done

lto=${IDRIS_MLIR_STAGE2_LTO:-Thin}
case $lto in
  Thin | Full) ;;
  *) usage "IDRIS_MLIR_STAGE2_LTO must be Thin or Full (got $lto)" ;;
esac
if [ -n "${IDRIS_MLIR_JOBS-}" ]; then
  jobs=$IDRIS_MLIR_JOBS
else
  cores=$(getconf _NPROCESSORS_ONLN 2> /dev/null) || cores=1
  memory_kib=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo 2> /dev/null) || memory_kib=0
  case $cores in '' | *[!0-9]*) cores=1 ;; esac
  case $memory_kib in '' | *[!0-9]*) memory_kib=0 ;; esac
  jobs=$((memory_kib / 5242880))
  if [ "$jobs" -gt "$cores" ]; then jobs=$cores; fi
  if [ "$jobs" -lt 1 ]; then jobs=1; fi
fi
case $jobs in
  '' | *[!0-9]* | 0) usage "IDRIS_MLIR_JOBS must be a positive number (got $jobs)" ;;
esac

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

[ -f "$lock" ] || die "$lock is missing"
schema=$(sed -n 's/^[[:space:]]*"schema_version"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$lock")
[ "$schema" = 4 ] || die "toolchain.lock.json has schema ${schema:-none}; tools/bootstrap.sh reads schema 4"
llvm_revision=$(lock_value llvm revision) || exit 1
llvm_tag=$(lock_value llvm tag) || exit 1
llvm_version=$(lock_value llvm version) || exit 1
llvm_major=${llvm_version%%.*}
cmake_revision=$(lock_value cmake revision) || exit 1
cmake_tag=$(lock_value cmake tag) || exit 1
cmake_version=$(lock_value cmake version) || exit 1
ninja_revision=$(lock_value ninja revision) || exit 1
ninja_tag=$(lock_value ninja tag) || exit 1
ninja_version=$(lock_value ninja version) || exit 1
musl_revision=$(lock_value musl revision) || exit 1
musl_version=$(lock_value musl version) || exit 1
gmp_revision=$(lock_value gmp revision) || exit 1
gmp_version=$(lock_value gmp version) || exit 1

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
  sha256sum | cut -c1-64
}

stamp_of() {
  case $1 in
    cmake) echo "$cmake_prefix/provenance.json" ;;
    ninja) echo "$ninja_prefix/provenance.json" ;;
    stage1) echo "$stage1/provenance.json" ;;
    musl | runtimes | gmp) echo "$sysroot/provenance/$1.json" ;;
    stage2) echo "$llvm_musl/provenance.json" ;;
    idris) echo "$idris_prefix/provenance.json" ;;
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

# build_dir [resume]: the step's build directory, $build. With `resume`, one
# that a failed run with the same inputs left is kept.
build_dir() {
  build=$builds/$step
  resumed=no
  if [ "${1-}" = resume ] && [ -f "$build/.inputs" ] && [ "$(cat "$build/.inputs")" = "$step_inputs" ]; then
    say "    resuming in $build"
    resumed=yes
  else
    rm -rf "$build"
    mkdir -p "$build"
    printf '%s\n' "$step_inputs" > "$build/.inputs"
  fi
}

size_mib() {
  du -sk "$1" 2> /dev/null | awk '{ print int($1 / 1024) }'
}

used_kib() {
  awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } END { print (t > 0 ? t - a : 0) }' /proc/meminfo 2> /dev/null || echo 0
}

# The most memory in use on the machine while a build runs,
# sampled every 5 seconds (there is no /usr/bin/time here).
sampler=
sample_memory() {
  peak_file=$logs/$step.peak
  baseline_kib=$(used_kib)
  echo "$baseline_kib" > "$peak_file"
  (
    peak=0
    while :; do
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

# static_pie READELF FILE: a static-PIE executable has a dynamic
# section, for its self-relocation, but no interpreter and no DT_NEEDED.
static_pie() {
  static_pie_out=$("$1" --file-header --program-headers --dynamic "$2") || die "$1 cannot read $2"
  case $static_pie_out in *'Type:'*DYN*) ;; *) die "$2 is not position-independent" ;; esac
  case $static_pie_out in *INTERP*) die "$2 has an interpreter" ;; esac
  case $static_pie_out in *NEEDED*) die "$2 needs a shared library" ;; esac
}

# clone_pinned TOOL DEST: a shallow clone of the lock's tag, at the lock's
# revision, unmodified.
clone_pinned() {
  clone_repository=$(lock_value "$1" repository) || exit 1
  clone_tag=$(lock_value "$1" tag) || exit 1
  clone_revision=$(lock_value "$1" revision) || exit 1
  if [ ! -e "$2/.git" ]; then
    rm -rf "$2"
    run "clone $1 $clone_tag" git clone --depth 1 --branch "$clone_tag" "$clone_repository" "$2"
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

# export_source PATH DEST: the pinned commit's files, with one timestamp, so
# no generated file looks stale and the checkout is never written to.
export_source() {
  rm -rf "$2"
  mkdir -p "$2"
  git -C "$root/$1" archive --format=tar HEAD | tar -xf - -C "$2" || die "cannot export $1"
  [ -f "$2/configure" ] || die "exporting $1 gave no configure script"
}

# verify_release TOOL PATH: the lock's release tarball, when it can be
# fetched, has the lock's SHA-256 and exactly the files of the pinned commit
# (PINS.md: mirrored-sources). Sets release_check.
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
  release_got=$(sha256sum "$release_dir/release" | cut -c1-64)
  [ "$release_got" = "$release_sha256" ] ||
    die "$release_url has SHA-256 $release_got; toolchain.lock.json records $release_sha256"
  tar -xf "$release_dir/release" -C "$release_dir/files" || die "cannot unpack $release_url"
  release_top=$(ls "$release_dir/files")
  [ -d "$release_dir/files/$release_top" ] || die "$release_url does not unpack into one directory"
  release_tree=$(cd "$release_dir/files/$release_top" && git init -q && git add -A -f && git write-tree) ||
    die "git cannot hash the files of $release_url"
  release_want=$(git -C "$root/$2" rev-parse 'HEAD^{tree}') || die "git rev-parse failed in $2"
  [ "$release_tree" = "$release_want" ] ||
    die "the files of $release_url (tree $release_tree) differ from $2 (tree $release_want)"
  release_check="verified against $release_url"
  say "    release: $release_check"
  rm -rf "$release_dir"
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

# The only configuration of the pinned clangs, next to them, which
# clang reads for its target (<CFGDIR> is the file's directory). Static-PIE is
# the only kind of executable: a shared link fails.
config_file() {
  cat << 'CFG'
# idris-mlir's toolchain for x86_64-unknown-linux-musl, written
# by tools/bootstrap.sh: musl, libc++ and GMP from the sysroot next to this
# clang; compiler-rt and libunwind; lld; static-PIE executables.
--sysroot=<CFGDIR>/../../sysroot
--rtlib=compiler-rt
--unwindlib=libunwind
-stdlib=libc++
-fuse-ld=lld
-static-pie
CFG
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
# of the host.
llvm_without_host_libraries() {
  printf '%s\n' -DLLVM_ENABLE_BINDINGS=OFF -DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBPFM=OFF \
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

# Only what the next steps use: the compilers, the linker, the
# archiver and nm for LTO objects, and readelf for the static-PIE checks.
stage1_components='clang;clang-resource-headers;lld;llvm-ar;llvm-ranlib;llvm-nm;llvm-readobj;llvm-readelf'

args_stage1() {
  printf '%s\n' -G Ninja -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_C_COMPILER=$host_cc" "-DCMAKE_CXX_COMPILER=$host_cxx" \
    "-DCMAKE_MAKE_PROGRAM=$ninja" "-DCMAKE_INSTALL_PREFIX=$stage1" \
    '-DLLVM_ENABLE_PROJECTS=clang;lld' -DLLVM_TARGETS_TO_BUILD=X86 \
    "-DLLVM_DEFAULT_TARGET_TRIPLE=$triple" -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF -DCLANG_PLUGIN_SUPPORT=OFF \
    "-DLLVM_DISTRIBUTION_COMPONENTS=$stage1_components"
  llvm_without_host_libraries
}

recipe_stage1() {
  printf '%s\n' "llvm $llvm_revision"
  args_stage1
  config_file
}

args_musl() {
  printf '%s\n' --prefix=/usr "--target=$triple" --disable-shared --disable-wrapper \
    "CC=$stage1/bin/clang" "AR=$stage1/bin/llvm-ar" "RANLIB=$stage1/bin/llvm-ranlib" \
    CFLAGS=-ffp-contract=off
}

recipe_musl() {
  recipe_stage1_inputs=$(inputs stage1) || exit 1
  printf '%s\n' "musl $musl_revision" "stage1 $recipe_stage1_inputs"
  args_musl
}

args_builtins() {
  printf '%s\n' -G Ninja -DCMAKE_BUILD_TYPE=Release
  stage1_tools
  printf '%s\n' -DCMAKE_DISABLE_FIND_PACKAGE_LLVM=ON -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
    -DCOMPILER_RT_BUILD_CRT=ON -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
    "-DCOMPILER_RT_INSTALL_PATH=$stage1/lib/clang/$llvm_major"
}

args_libcxx() {
  printf '%s\n' -G Ninja -DCMAKE_BUILD_TYPE=Release
  stage1_tools
  printf '%s\n' -DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON \
    -DCMAKE_ASM_COMPILER_WORKS=ON -DCMAKE_INSTALL_PREFIX=/usr \
    '-DLLVM_ENABLE_RUNTIMES=libunwind;libcxxabi;libcxx' \
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_DOCS=OFF \
    -DLIBUNWIND_ENABLE_SHARED=OFF -DLIBUNWIND_USE_COMPILER_RT=ON \
    -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXXABI_USE_COMPILER_RT=ON -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXX_USE_COMPILER_RT=ON -DLIBCXX_HAS_MUSL_LIBC=ON \
    -DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY=ON \
    -DLIBCXX_ENABLE_TIME_ZONE_DATABASE=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF
}

recipe_runtimes() {
  recipe_stage1_inputs=$(inputs stage1) || exit 1
  recipe_musl_inputs=$(inputs musl) || exit 1
  printf '%s\n' "llvm $llvm_revision" "stage1 $recipe_stage1_inputs" "musl $recipe_musl_inputs"
  args_builtins
  args_libcxx
}

# What stage 2 installs.
stage2_components='clang;clang-scan-deps;clang-resource-headers;lld;clang-tidy;llvm-ar;llvm-ranlib;llvm-nm;llvm-objcopy;llvm-strip;llvm-objdump;llvm-readobj;llvm-readelf;llvm-symbolizer;opt;llc;FileCheck;not;count;mlir-opt;mlir-translate;mlir-tblgen;llvm-headers;llvm-libraries;cmake-exports;mlir-headers;mlir-libraries;mlir-cmake-exports'

# Stage 2. Static PIE on musl and libc++ (the configuration file),
# no shared libraries or plugins, LTO with fat objects: their bitcode serves
# the Release build of our tools, their native code every other build. A
# ThinLTO link runs two backend threads, so that it and two compile jobs fit
# in 15 GB of memory.
# PIN(stage2-thinlto): ThinLTO unless IDRIS_MLIR_STAGE2_LTO=Full — see PINS.md
args_stage2() {
  printf '%s\n' -G Ninja -DCMAKE_BUILD_TYPE=Release
  stage1_tools
  printf '%s\n' "-DCMAKE_LINKER=$stage1/bin/ld.lld" -DCMAKE_EXE_LINKER_FLAGS=-Wl,--thinlto-jobs=2 \
    "-DCMAKE_INSTALL_PREFIX=$llvm_musl" \
    '-DLLVM_ENABLE_PROJECTS=clang;lld;mlir;clang-tools-extra' -DLLVM_TARGETS_TO_BUILD=X86 \
    "-DLLVM_HOST_TRIPLE=$triple" "-DLLVM_DEFAULT_TARGET_TRIPLE=$triple" \
    -DLLVM_ENABLE_ASSERTIONS=ON -DLLVM_ENABLE_RTTI=OFF -DLLVM_ENABLE_EH=OFF \
    -DLLVM_ENABLE_LIBCXX=ON -DLLVM_ENABLE_PIC=OFF -DLLVM_BUILD_STATIC=ON \
    "-DLLVM_ENABLE_LTO=$lto" -DLLVM_ENABLE_FATLTO=ON -DLLVM_INSTALL_UTILS=ON \
    -DMLIR_INSTALL_AGGREGATE_OBJECTS=OFF -DCLANG_PLUGIN_SUPPORT=OFF \
    "-DLLVM_DISTRIBUTION_COMPONENTS=$stage2_components"
  llvm_without_host_libraries
}

recipe_stage2() {
  recipe_stage1_inputs=$(inputs stage1) || exit 1
  recipe_musl_inputs=$(inputs musl) || exit 1
  recipe_runtimes_inputs=$(inputs runtimes) || exit 1
  printf '%s\n' "llvm $llvm_revision" "stage1 $recipe_stage1_inputs" \
    "musl $recipe_musl_inputs" "runtimes $recipe_runtimes_inputs"
  args_stage2
  config_file
}

args_gmp() {
  printf '%s\n' --prefix=/usr --build=x86_64-pc-linux-musl --host=x86_64-pc-linux-musl \
    --enable-fat --with-pic --disable-shared --enable-static \
    "CC=$llvm_musl/bin/clang" 'CFLAGS=-O2 -pipe -ffp-contract=off' \
    "AR=$llvm_musl/bin/llvm-ar" "NM=$llvm_musl/bin/llvm-nm" "RANLIB=$llvm_musl/bin/llvm-ranlib"
}

recipe_gmp() {
  recipe_stage2_inputs=$(inputs stage2) || exit 1
  printf '%s\n' "gmp $gmp_revision" "stage2 $recipe_stage2_inputs"
  args_gmp
}

find_chez() {
  if [ -n "${CHEZ-}" ]; then
    command -v "$CHEZ" 2> /dev/null || die "CHEZ=$CHEZ is not an executable"
    return 0
  fi
  for chez_name in chezscheme scheme chez chez-scheme; do
    if command -v "$chez_name" 2> /dev/null; then return 0; fi
  done
  die "Chez Scheme not found: install it or set CHEZ"
}

recipe_idris() {
  recipe_idris_revision=$(submodule third_party/Idris2) || exit 1
  recipe_chez=$(find_chez) || exit 1
  recipe_chez_version=$("$recipe_chez" --version 2>&1 | head -n 1)
  printf '%s\n' "idris2 $recipe_idris_revision" "scheme $recipe_chez" \
    "scheme version $recipe_chez_version" "make bootstrap install install-api"
}

# --- Steps --------------------------------------------------------------

step_cmake() {
  begin cmake "CMake $cmake_tag, with the host's C++ compiler" || return 0
  need git make "$host_cc" "$host_cxx"
  build_dir
  clone_pinned cmake "$build/src"
  eval "set -- $(args_cmake | quote_lines)"
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
  eval "set -- $(args_ninja | quote_lines)"
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

# Stage 1, the host compiler's clang and lld; nothing else.
step_stage1() {
  begin stage1 "clang and lld $llvm_tag, with the host's C++ compiler" || return 0
  require cmake ninja
  need git python3 "$host_cc" "$host_cxx"
  clone_pinned llvm "$llvm_source"
  build_dir resume
  if [ "$resumed" = no ]; then need_disk 8 "the stage-1 build"; fi
  eval "set -- $(args_stage1 | quote_lines)"
  sample_memory
  run configure "$cmake" -S "$llvm_source/llvm" -B "$build" "$@" \
    "-DPython3_EXECUTABLE=$(command -v python3)" \
    "-DLLVM_PARALLEL_COMPILE_JOBS=$jobs" -DLLVM_PARALLEL_LINK_JOBS=1
  run "build (hours; progress in the log)" "$ninja" -C "$build" -j "$jobs" distribution
  build_mib=$(size_mib "$build")
  # The builtins live in stage 1's resource directory, so they go with it.
  rm -rf "$stage1"
  rm -f "$(stamp_of runtimes)"
  run install "$ninja" -C "$build" install-distribution
  stop_sampling
  config_file > "$stage1/bin/$triple.cfg"
  version_is "$stage1/bin/clang" "clang version $llvm_version"
  version_is "$stage1/bin/ld.lld" "LLD $llvm_version"
  [ "$("$stage1/bin/clang" -print-resource-dir)" = "$stage1/lib/clang/$llvm_major" ] ||
    die "stage 1's resource directory is not $stage1/lib/clang/$llvm_major"
  write_stamp "$(stamp_of stage1)" step stage1 revision "$llvm_revision" tag "$llvm_tag" \
    version "$llvm_version" inputs "$step_inputs" \
    host_compiler "$("$host_cxx" --version 2>&1 | head -n 1)" jobs "$jobs" \
    seconds "$(($(date +%s) - started))" peak_memory_mib "$((peak_kib / 1024))" \
    baseline_memory_mib "$((baseline_kib / 1024))" build_dir_mib "$build_mib" \
    install_mib "$(size_mib "$stage1")" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish
}

# musl, with stage 1, and the kernel's UAPI headers, which musl
# does not ship and libc++ and snmalloc include (PIN(linux-uapi-from-host)).
step_musl() {
  begin musl "musl $musl_version, with stage 1" || return 0
  require stage1
  need git make
  submodule third_party/musl musl > /dev/null
  verify_release musl third_party/musl
  uapi=
  for uapi_candidate in /usr/include/x86_64-linux-gnu /usr/include; do
    if [ -f "$uapi_candidate/asm/unistd.h" ]; then uapi=$uapi_candidate; break; fi
  done
  if [ -z "$uapi" ] || [ ! -f /usr/include/linux/futex.h ] || [ ! -d /usr/include/asm-generic ]; then
    die "the host's Linux UAPI headers are missing; install its kernel headers package (linux-libc-dev)"
  fi
  build_dir
  export_source third_party/musl "$build/src"
  mkdir -p "$build/out"
  rm -rf "$sysroot"
  mkdir -p "$sysroot/usr/include"
  eval "set -- $(args_musl | quote_lines)"
  run configure in_dir "$build/out" "$build/src/configure" "$@"
  run build in_dir "$build/out" make -j "$jobs"
  run install in_dir "$build/out" make install "DESTDIR=$sysroot"
  run "the host's Linux UAPI headers" cp -RL /usr/include/linux /usr/include/asm-generic "$uapi/asm" "$sysroot/usr/include/"
  for musl_file in usr/lib/libc.a usr/lib/rcrt1.o usr/lib/crti.o usr/lib/crtn.o usr/include/stdio.h \
    usr/include/linux/futex.h usr/include/asm/unistd.h; do
    [ -f "$sysroot/$musl_file" ] || die "the musl step installed no $musl_file"
  done
  uapi_sha256=$(cd "$sysroot/usr/include" && find linux asm asm-generic -type f | sort | xargs sha256sum | digest)
  uapi_package=$(dpkg-query -W -f='${Version}' linux-libc-dev 2> /dev/null) || uapi_package=unknown
  write_stamp "$(stamp_of musl)" step musl revision "$musl_revision" version "$musl_version" \
    inputs "$step_inputs" release "$release_check" uapi_headers "$uapi" \
    uapi_package "$uapi_package" uapi_sha256 "$uapi_sha256" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish
}

# The LLVM runtimes, with stage 1, for musl.
step_runtimes() {
  begin runtimes "compiler-rt's builtins, libunwind, libc++abi and libc++, with stage 1" || return 0
  require stage1 musl
  need git python3
  clone_pinned llvm "$llvm_source"
  resource=$stage1/lib/clang/$llvm_major
  build_dir
  rm -rf "$resource/lib/$triple"
  eval "set -- $(args_builtins | quote_lines)"
  run "configure the builtins" "$cmake" -S "$llvm_source/compiler-rt/lib/builtins" -B "$build/builtins" "$@"
  run "build the builtins" "$ninja" -C "$build/builtins" -j "$jobs"
  run "install the builtins" "$ninja" -C "$build/builtins" install
  for builtins_file in libclang_rt.builtins.a clang_rt.crtbegin.o clang_rt.crtend.o; do
    [ -f "$resource/lib/$triple/$builtins_file" ] || die "the builtins build installed no $resource/lib/$triple/$builtins_file"
  done
  eval "set -- $(args_libcxx | quote_lines)"
  run "configure libunwind, libc++abi and libc++" "$cmake" -S "$llvm_source/runtimes" -B "$build/runtimes" "$@" \
    "-DPython3_EXECUTABLE=$(command -v python3)"
  run "build libunwind, libc++abi and libc++" "$ninja" -C "$build/runtimes" -j "$jobs"
  run "install libunwind, libc++abi and libc++" env "DESTDIR=$build/stage" "$ninja" -C "$build/runtimes" install
  install_staged runtimes "$build/stage"
  cat > "$build/check.cc" << 'CC'
#include <cstdio>
#include <string>
#include <vector>
int main() {
  std::vector<std::string> words{"libc++", "on", "musl"};
  std::string line;
  for (const auto &word : words) line += word + " ";
  try { throw 42; } catch (int) { std::printf("%sok\n", line.c_str()); return 0; }
  return 1;
}
CC
  run "check: a static-PIE C++ program with exceptions" "$stage1/bin/clang++" -std=c++20 -O2 "$build/check.cc" -o "$build/check"
  [ "$("$build/check")" = "libc++ on musl ok" ] || die "the C++ check program did not print its line"
  static_pie "$stage1/bin/llvm-readelf" "$build/check"
  write_stamp "$(stamp_of runtimes)" step runtimes revision "$llvm_revision" tag "$llvm_tag" \
    inputs "$step_inputs" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish
}

# Stage 2, with stage 1, on musl and libc++.
step_stage2() {
  begin stage2 "LLVM/MLIR, clang, lld and clang-tidy $llvm_tag, with stage 1 ($lto LTO)" || return 0
  require cmake ninja stage1 musl runtimes
  need git python3
  # Objects that carry bitcode and native code, then one copy of
  # the libraries installed; measured, the stamp says how much it took.
  clone_pinned llvm "$llvm_source"
  build_dir resume
  if [ "$resumed" = no ]; then need_disk 13 "the stage-2 build and install"; fi
  eval "set -- $(args_stage2 | quote_lines)"
  sample_memory
  run configure "$cmake" -S "$llvm_source/llvm" -B "$build" "$@" \
    "-DPython3_EXECUTABLE=$(command -v python3)" \
    "-DLLVM_PARALLEL_COMPILE_JOBS=$jobs" -DLLVM_PARALLEL_LINK_JOBS=1
  run "build (many hours; progress in the log)" "$ninja" -C "$build" -j "$jobs" distribution
  build_mib=$(size_mib "$build")
  # The libraries hold the objects now. Deleting the objects before the
  # install keeps one copy of them on disk; the install commands are those of
  # install-distribution, run without Ninja, which would rebuild the objects.
  rm -f "$build/.inputs"
  "$ninja" -C "$build" -t commands install-distribution | grep -e '-DCMAKE_INSTALL_COMPONENT=' > "$build/install.sh" ||
    die "stage 2 has no install commands"
  find "$build" -name '*.o' -type f -exec rm -f {} +
  rm -rf "$llvm_musl"
  run install sh -e "$build/install.sh"
  stop_sampling
  for stage2_file in bin/clang bin/clang++ bin/ld.lld bin/clang-tidy bin/opt bin/llc bin/llvm-nm \
    bin/llvm-ar bin/llvm-readelf bin/mlir-opt bin/mlir-translate bin/mlir-tblgen bin/FileCheck \
    bin/not bin/count lib/cmake/llvm/LLVMConfig.cmake lib/cmake/mlir/MLIRConfig.cmake \
    lib/libLLVMSupport.a lib/libMLIRIR.a include/mlir/IR/MLIRContext.h \
    "lib/clang/$llvm_major/include/stddef.h"; do
    [ -e "$llvm_musl/$stage2_file" ] || die "stage 2 installed no $stage2_file"
  done
  mkdir -p "$llvm_musl/lib/clang/$llvm_major/lib"
  cp -R "$stage1/lib/clang/$llvm_major/lib/$triple" "$llvm_musl/lib/clang/$llvm_major/lib/"
  config_file > "$llvm_musl/bin/$triple.cfg"
  version_is "$llvm_musl/bin/clang" "clang version $llvm_version"
  version_is "$llvm_musl/bin/ld.lld" "LLD $llvm_version"
  version_is "$llvm_musl/bin/mlir-opt" "LLVM version $llvm_version"
  version_is "$llvm_musl/bin/FileCheck" "LLVM version $llvm_version"
  static_pie "$llvm_musl/bin/llvm-readelf" "$llvm_musl/bin/clang"
  static_pie "$llvm_musl/bin/llvm-readelf" "$llvm_musl/bin/mlir-opt"
  mkdir -p "$build/check"
  printf '#include <stdio.h>\nint main(void) { puts("c ok"); return 0; }\n' > "$build/check/c.c"
  printf '#include <cstdio>\n#include <vector>\nint main() { std::vector<int> v{1, 2}; std::printf("c++ ok %%zu\\n", v.size()); }\n' > "$build/check/cc.cc"
  run "check: static-PIE C and C++ programs" "$llvm_musl/bin/clang" -O2 "$build/check/c.c" -o "$build/check/c"
  run "check: a C++26 program" "$llvm_musl/bin/clang++" -std=c++26 -O2 "$build/check/cc.cc" -o "$build/check/cc"
  [ "$("$build/check/c")" = "c ok" ] || die "the C check program did not print its line"
  [ "$("$build/check/cc")" = "c++ ok 2" ] || die "the C++ check program did not print its line"
  static_pie "$llvm_musl/bin/llvm-readelf" "$build/check/cc"
  write_stamp "$(stamp_of stage2)" step stage2 revision "$llvm_revision" llvm_revision "$llvm_revision" \
    tag "$llvm_tag" version "$llvm_version" lto "$lto" fat_lto_objects yes inputs "$step_inputs" \
    jobs "$jobs" seconds "$(($(date +%s) - started))" peak_memory_mib "$((peak_kib / 1024))" \
    baseline_memory_mib "$((baseline_kib / 1024))" build_dir_mib "$build_mib" \
    install_mib "$(size_mib "$llvm_musl")" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish
}

# GMP, with the stage-2 clang: static, position-independent, with every
# x86-64 kernel selected at run time.
step_gmp() {
  begin gmp "GMP $gmp_version, with the stage-2 clang" || return 0
  require stage2 musl runtimes
  need git make m4
  submodule third_party/gmp gmp > /dev/null
  verify_release gmp third_party/gmp
  build_dir
  export_source third_party/gmp "$build/src"
  mkdir -p "$build/out"
  eval "set -- $(args_gmp | quote_lines)"
  run configure in_dir "$build/out" "$build/src/configure" "$@"
  run build in_dir "$build/out" make -j "$jobs"
  run "check (GMP's tests)" in_dir "$build/out" make -j "$jobs" check
  run install in_dir "$build/out" make install "DESTDIR=$build/stage"
  rm -rf "$build/stage/usr/share" "$build/stage/usr/lib/libgmp.la"
  install_staged gmp "$build/stage"
  printf '#include <gmp.h>\n#include <stdio.h>\nint main(void) { mpz_t x; mpz_init(x); mpz_ui_pow_ui(x, 2, 100); gmp_printf("%%Zd\\n", x); mpz_clear(x); return 0; }\n' > "$build/check.c"
  run "check: a static-PIE GMP program" "$llvm_musl/bin/clang" -O2 "$build/check.c" -o "$build/check" -lgmp
  [ "$("$build/check")" = 1267650600228229401496703205376 ] || die "the GMP check program did not print 2^100"
  static_pie "$llvm_musl/bin/llvm-readelf" "$build/check"
  write_stamp "$(stamp_of gmp)" step gmp revision "$gmp_revision" version "$gmp_version" \
    inputs "$step_inputs" release "$release_check" built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finish
}

# Idris 2 on the host's Chez Scheme. Its C support library is a
# shared object in the host's Chez process, so the host's C compiler builds
# it. PIN(idris-support-host-cc) — see PINS.md
step_idris() {
  begin idris "Idris 2 and its API, on the host's Chez Scheme" || return 0
  need git make
  idris_revision=$(submodule third_party/Idris2) || exit 1
  chez=$(find_chez) || exit 1
  build=$builds/idris
  rm -rf "$idris_prefix"
  run bootstrap idris_make bootstrap
  run install idris_make install
  run "install the API" idris_make install-api "IDRIS2_BOOT=$idris_prefix/bin/idris2"
  "$idris_prefix/bin/idris2" --version > /dev/null 2>&1 || die "the installed idris2 does not run"
  write_stamp "$(stamp_of idris)" step idris idris2_revision "$idris_revision" scheme "$chez" \
    scheme_version "$("$chez" --version 2>&1 | head -n 1)" inputs "$step_inputs" \
    built "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
    cd "$root/third_party/Idris2" && make "$@" "PREFIX=$idris_prefix" "SCHEME=$chez"
  )
}

# --- Main ---------------------------------------------------------------

mkdir -p "$toolchain"
mutex=$toolchain/.bootstrap.lock
mkdir "$mutex" 2> /dev/null ||
  die "another tools/bootstrap.sh is running; if none is, remove $mutex"
cleanup() {
  if [ -n "$sampler" ]; then kill "$sampler" 2> /dev/null || true; fi
  rmdir "$mutex" 2> /dev/null || true
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

say "tools/bootstrap.sh:$steps ($jobs jobs; stage-2 LTO $lto)"
summary=
for step in $steps; do
  "step_$step"
done
say "==> summary:$summary"
