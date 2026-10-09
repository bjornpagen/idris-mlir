# Where the pinned tools are, in one place: sourced, with $root
# set to the repository, by the Makefile, tools/compile.sh, tools/bisect.sh,
# tools/verify-pins.sh, tools/doctor.sh, bench/run.sh, tests/testutils.sh and
# tests/upstream-idris/as-idris.
# IDRIS_MLIR_TOOLCHAIN stands for .toolchain (the spec tests use it).

toolchain=${IDRIS_MLIR_TOOLCHAIN:-$root/.toolchain}
# The pinned Chez Scheme: Idris 2 runs on it, and so do the programs of
# Idris's Chez backend, the tests' runner and bench/'s baseline.
chez_prefix=$toolchain/chez
chez_scheme=$chez_prefix/bin/scheme
# Idris 2 and its libraries, built from third_party/Idris2 on that Chez.
idris_prefix=$toolchain/idris2
idris2=$idris_prefix/bin/idris2
# The prefix the frontend runs with (`make prefix`, `make libs`): this
# checkout's own, holding only what its frontend built, in the TTC format of
# the fork of Idris's compiler it links (compiler/idris): the packages the
# pinned Idris source ships (prelude, base and the others) and those of
# libs/. No checkout (a worktree too) compiles against another's.
checkout_prefix=$root/build/idris2
# Where the pinned Idris installs the packages this checkout builds for it
# (`make fork`): the fork, which it builds the frontend against. Its format
# is the pinned Idris's, so it is never part of checkout_prefix, and the
# pinned prefix is shared by every checkout.
host_prefix=$root/build/idris2-host
# The file each step of `make build` leaves in its prefix once it is done,
# which tools/verify-pins.sh and tools/doctor.sh read: in host_prefix, the
# fork installed (`make fork`) and the packages of libs/ (`make host-libs`);
# in checkout_prefix, the pinned Idris source's packages (`make prefix`)
# and those of libs/ (`make libs`).
fork_stamp=.fork-installed
host_libs_stamp=.libs-installed
prefix_stamp=.built
libs_stamp=.libs-installed
# The stage-2 LLVM/MLIR: clang, lld, mlir-opt, mlir-translate,
# opt, llc, llvm-nm, FileCheck, not, count, with the runtimes beside them,
# their configuration file and the CMake toolchain file every preset reads.
# One prefix on every host (tools/bootstrap.sh).
llvm_prefix=$toolchain/llvm
llvm_bin=$llvm_prefix/bin
# The configure preset `make build` uses (CMakePresets.json) and the
# directory it builds into, build/<preset>.
dev_preset=dev
dev_prefix=$root/build/$dev_preset
# The C compiler that links programs (idris-mlir, whose build records it, the
# benchmarks' C, the tests that link by hand): the stage-2 clang, whose
# configuration file, read for the target its callers name, gives the
# target's C library, the runtimes, lld and the kind of executable.
pinned_cc=$llvm_bin/clang
# The sysroot programs link against: the target's C library where it is
# built (musl), and GMP.
sysroot=$toolchain/sysroot
cmake=$toolchain/cmake/bin/cmake
# What `make build` makes: idris-mlir, the one command, with its frontend
# beside it, where idris-mlir runs it (a link to the frontend Idris
# builds, compiler/build/exec/idris-mlir-front), and the dialect's tools.
idris_mlir=$dev_prefix/foreign/idr/idris-mlir
idris_mlir_front=$dev_prefix/foreign/idr/idris-mlir-front
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
