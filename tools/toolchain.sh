# Where the pinned tools are, in one place: sourced, with $root
# set to the repository, by the Makefile, tools/compile.sh,
# tools/verify-pins.sh, tools/doctor.sh, bench/run.sh and tests/testutils.sh.
# IDRIS_MLIR_TOOLCHAIN stands for .toolchain (the spec tests use it).

toolchain=${IDRIS_MLIR_TOOLCHAIN:-$root/.toolchain}
# The pinned Chez Scheme: Idris 2 runs on it, and so do the programs of
# Idris's Chez backend, the tests' oracle.
chez_prefix=$toolchain/chez
chez_scheme=$chez_prefix/bin/scheme
# Idris 2 and its libraries, built from third_party/Idris2 on that Chez.
idris_prefix=$toolchain/idris2
idris2=$idris_prefix/bin/idris2
# The prefix every command runs that Idris with (`make prefix`): this
# checkout's own, the pinned prefix's packages linked and the packages of
# libs/ installed as this checkout builds them, so that no checkout (a
# worktree too) compiles against another's libs/.
checkout_prefix=$root/build/idris2
# The stage-2 LLVM/MLIR: clang, lld, mlir-opt, mlir-translate,
# opt, llc, llvm-nm, FileCheck, not, count. Its prefix is the host's: the
# Linux build pins musl/libc++ into .toolchain/llvm-musl, the Darwin build
# is one native stage in .toolchain/llvm-macos (tools/bootstrap.sh).
case $(uname -s) in
  Darwin) llvm_prefix=$toolchain/llvm-macos ;;
  *) llvm_prefix=$toolchain/llvm-musl ;;
esac
llvm_bin=$llvm_prefix/bin
# The configure preset `make build` uses (CMakePresets.json) and the
# directory it builds into: the Darwin preset is the same build with
# .toolchain/llvm-macos as the pinned compiler, into build/dev-darwin (its
# preset name).
case $(uname -s) in
  Darwin) dev_preset=dev-darwin ;;
  *) dev_preset=dev ;;
esac
dev_prefix=$root/build/$dev_preset
# The C compiler that links programs (both compile flows, the benchmarks): the
# stage-2 clang, whose configuration file names the sysroot, compiler-rt,
# libunwind, lld and static-PIE output on Linux, and the SDK and the pinned
# runtimes on Darwin.
pinned_cc=$llvm_bin/clang
# The sysroot programs link against: musl, the LLVM runtimes and GMP on
# Linux; GMP alone on Darwin, whose C library is libSystem in the SDK.
sysroot=$toolchain/sysroot
cmake=$toolchain/cmake/bin/cmake
# What `make build` makes.
idris_mlir_cc=$dev_prefix/foreign/idr/idris-mlir-cc
idris_mlir_opt=$dev_prefix/foreign/idr/idris-mlir-opt
idris_mlir_tblgen=$dev_prefix/foreign/idr/idris-mlir-tblgen

# stamp_field PREFIX KEY: a string of PREFIX/provenance.json, the stamp a
# bootstrap writes once every step of it succeeded.
stamp_field() {
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$1/provenance.json" 2> /dev/null | head -n 1
}

# The host's tools where Linux and macOS differ: coreutils' timeout
# ($timeout_cmd), the nanosecond clock, SHA-256 and the stack limit.
. "$root/tools/host.sh"
