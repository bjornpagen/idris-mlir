# Where the pinned tools are (TC-PIN-2), in one place: sourced, with $root
# set to the repository, by the Makefile, tools/compile.sh,
# tools/verify-pins.sh, tools/doctor.sh, bench/run.sh and tests/testutils.sh.
# IDRIS_MLIR_TOOLCHAIN stands for .toolchain (the spec tests use it).

toolchain=${IDRIS_MLIR_TOOLCHAIN:-$root/.toolchain}
# Idris 2 and its libraries, built from third_party/Idris2.
idris_prefix=$toolchain/idris2
idris2=$idris_prefix/bin/idris2
# The stage-2 LLVM/MLIR (TC-BOOT-2): clang, lld, mlir-opt, mlir-translate,
# opt, llc, llvm-nm, FileCheck, not, count.
llvm_bin=$toolchain/llvm-musl/bin
# The C compiler that links programs (DRV-FLOW-1, DRV-FLOW-2, the
# benchmarks): the stage-2 clang, whose configuration file names the sysroot,
# compiler-rt, libunwind, lld and static-PIE output (TC-BOOT-5).
pinned_cc=$llvm_bin/clang
# musl, the LLVM runtimes and GMP, which programs link against (TC-BOOT-4).
sysroot=$toolchain/sysroot
cmake=$toolchain/cmake/bin/cmake
# What `make build` makes.
idris_mlir_cc=$root/build/dev/foreign/idr/idris-mlir-cc
idris_mlir_opt=$root/build/dev/foreign/idr/idris-mlir-opt

# stamp_field PREFIX KEY: a string of PREFIX/provenance.json, the stamp a
# bootstrap writes once every step of it succeeded.
stamp_field() {
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$1/provenance.json" 2> /dev/null | head -n 1
}
