# Shared by the memory gate's scripts (bench/gate/README.md); POSIX sh, to be
# sourced with GATE set to bench/gate.
#
# Environment:
#   GATE_OUT      where builds and results go (default build/gate)
#   RUNS          runs per measurement, best time kept (default 5)
#   SNMALLOC_SRC  snmalloc's src/ (default third_party/snmalloc/src)
#   CXX           the C++ compiler for the runtime prototype (default: the
#                 pinned LLVM's clang++ if there is one, else the pinned g++)

ROOT=$(cd "$GATE/../.." && pwd)
TC=$ROOT/.toolchain
OUT=${GATE_OUT:-$ROOT/build/gate}
RUNS=${RUNS:-5}
SNMALLOC_SRC=${SNMALLOC_SRC:-$ROOT/third_party/snmalloc/src}

LLVM_BIN=$TC/llvm/bin
MLTON=$TC/mlton/usr/bin/mlton
IDRIS2=$TC/idris2/bin/idris2
KOKA=$TC/koka/bin/koka
LEAN_BIN=$TC/lean/bin
GOROOT_DIR=$TC/go/usr/lib/go-1.24

if [ -z "${CXX:-}" ]; then
  if [ -x "$LLVM_BIN/clang++" ]; then CXX=$LLVM_BIN/clang++
  elif [ -x "$TC/gcc/bin/g++" ]; then CXX=$TC/gcc/bin/g++
  else CXX=c++; fi
fi
if [ -z "${CC:-}" ]; then
  if [ -x "$TC/gcc/bin/gcc" ]; then CC=$TC/gcc/bin/gcc; else CC=cc; fi
fi

# The target of the lowered programs and of the runtime: the plan's default
# CPU from milestone 1 on (plan 5.7).
TRIPLE=x86_64-unknown-linux-gnu
CPU=x86-64-v3

# The input of each program: the papers' sizes for the suite (Perceus's for
# rbtree, rbtree-ck, deriv, nqueens and cfold; Lean's for qsort and
# unionfind; the Benchmarks Game's for binarytrees). GATE_SMALL=1 selects
# small inputs, to check the scripts and the outputs quickly; its times mean
# nothing.
input_of() {
  if [ "${GATE_SMALL:-0}" = 1 ]; then
    case $1 in
      rbtree|rbtree-ck|linrb|linrb-shared) echo 100000 ;;
      deriv) echo 7 ;;
      nqueens) echo 8 ;;
      cfold) echo 14 ;;
      binarytrees|ptrees) echo 12 ;;
      qsort) echo 40 ;;
      unionfind) echo 70000 ;;
      shmap) echo "10000 20000" ;;
      pipe) echo "2000 6" ;;
      *) echo "gate: no input for $1" >&2; return 1 ;;
    esac
    return 0
  fi
  case $1 in
    rbtree|rbtree-ck) echo 4200000 ;;
    deriv) echo 10 ;;
    nqueens) echo 13 ;;
    cfold) echo 20 ;;
    binarytrees|ptrees) echo 21 ;;
    qsort) echo 400 ;;
    unionfind) echo 3000000 ;;
    linrb|linrb-shared) echo 4200000 ;;
    shmap) echo "1000000 1000000" ;;   # map size, lookups per core
    pipe) echo "20000 10" ;;           # trees per pair, depth
    *) echo "gate: no input for $1" >&2; return 1 ;;
  esac
}

SUITE="rbtree rbtree-ck deriv nqueens cfold binarytrees qsort unionfind"

say() { printf '%s\n' "$*" >&2; }
die() { say "gate: $*"; exit 1; }

# The file name of benchmark $1 in a language other than Koka and Idris.
base_of() { printf '%s' "$1" | tr - _; }

# fresh TARGET SOURCE...: true when TARGET exists and is newer than every
# SOURCE, so a build can be skipped.
fresh() {
  target=$1; shift
  [ -e "$target" ] || return 1
  for s in "$@"; do [ "$s" -nt "$target" ] && return 1; done
  return 0
}

# The measuring tool (tools/measure.c).
MEASURE=$OUT/bin/measure
build_measure() {
  mkdir -p "$OUT/bin"
  fresh "$MEASURE" "$GATE/tools/measure.c" ||
    "$CC" -O2 -o "$MEASURE" "$GATE/tools/measure.c" || die "cannot build measure"
}

have_idris() { [ -x "$IDRIS2" ] && [ -f "$TC/idris2/provenance.json" ]; }
have_mlton() { [ -x "$MLTON" ]; }
have_koka() { [ -x "$KOKA" ]; }
have_lean() { [ -x "$LEAN_BIN/lean" ] && [ -x "$LEAN_BIN/leanc" ]; }
have_go() { [ -x "$GOROOT_DIR/bin/go" ]; }
have_llvm() { [ -x "$LLVM_BIN/mlir-opt" ] && [ -x "$LLVM_BIN/mlir-translate" ] && [ -x "$LLVM_BIN/opt" ] && [ -x "$LLVM_BIN/llc" ]; }
have_snmalloc() { [ -f "$SNMALLOC_SRC/snmalloc/snmalloc.h" ]; }

# Runs the Idris compiler of .toolchain/idris2 as the Makefile does: no
# inherited package paths, and the Chez Scheme it was built with.
idris() {
  scheme=$(sed -n 's/.*"scheme": *"\([^"]*\)".*/\1/p' "$TC/idris2/provenance.json")
  env -u IDRIS2_PATH -u IDRIS2_PACKAGE_PATH -u IDRIS2_INC_CGS -u IDRIS2_DATA \
      -u IDRIS2_LIBS -u IDRIS2_CG -u IDRIS2_BOOT \
      IDRIS2_PREFIX="$TC/idris2" PATH="$TC/idris2/bin:$PATH" CHEZ="$scheme" \
      "$IDRIS2" --no-color --no-banner "$@"
}

# ---- builds: each prints the path of the executable, or fails ----------------
#
# build_LANG DIR NAME: DIR holds the sources, NAME is the benchmark.

build_chez() {
  dir=$1; name=$2; out=$OUT/chez/$name
  exe=$out/exec/prog
  fresh "$exe" "$dir/Main.idr" && { echo "$exe"; return 0; }
  mkdir -p "$out"
  (cd "$dir" && idris --cg chez --build-dir "$out/build" --output-dir "$out/exec" -o prog Main.idr) \
    > "$out/build.log" 2>&1 || { say "Idris (Chez) failed on $name: $out/build.log"; return 1; }
  echo "$exe"
}

build_mlton() {
  dir=$1; name=$2; src=$dir/$(base_of "$name").sml; exe=$OUT/mlton/$name
  fresh "$exe" "$src" && { echo "$exe"; return 0; }
  mkdir -p "$OUT/mlton"
  # Idris's Int has 64 bits; MLton's default int has 32 (bench/README.md).
  "$MLTON" -default-type int64 -output "$exe" "$src" > "$exe.log" 2>&1 ||
    { say "MLton failed on $name: $exe.log"; return 1; }
  echo "$exe"
}

build_c() {
  dir=$1; name=$2; src=$dir/$(base_of "$name").c; exe=$OUT/c/$name
  fresh "$exe" "$src" && { echo "$exe"; return 0; }
  mkdir -p "$OUT/c"
  "$CC" -O2 -o "$exe" "$src" > "$exe.log" 2>&1 || { say "C failed on $name: $exe.log"; return 1; }
  echo "$exe"
}

build_koka() {
  dir=$1; name=$2; src=$name.kk; exe=$OUT/koka/$name
  fresh "$exe" "$dir/$src" && { echo "$exe"; return 0; }
  mkdir -p "$OUT/koka"
  # The Perceus benchmarks' flags: -O2 and a 128 MiB stack.
  (cd "$dir" && "$KOKA" -O2 --stack=128M --builddir="$OUT/koka/.build" -o "$exe" "$src") \
    > "$exe.log" 2>&1 || { say "Koka failed on $name: $exe.log"; return 1; }
  echo "$exe"
}

build_lean() {
  dir=$1; name=$2; src=$dir/$(base_of "$name").lean; exe=$OUT/lean/$name
  fresh "$exe" "$src" && { echo "$exe"; return 0; }
  mkdir -p "$OUT/lean"
  # As Lean's own benchmarks: lean emits C, leanc -O3 -DNDEBUG compiles it.
  { "$LEAN_BIN/lean" -c "$exe.c" "$src" && "$LEAN_BIN/leanc" -O3 -DNDEBUG -o "$exe" "$exe.c"; } \
    > "$exe.log" 2>&1 || { say "Lean failed on $name: $exe.log"; return 1; }
  echo "$exe"
}

build_go() {
  dir=$1; name=$2; src=$dir/$(base_of "$name").go; exe=$OUT/go/$name
  fresh "$exe" "$src" && { echo "$exe"; return 0; }
  mkdir -p "$OUT/go/.cache"
  GOROOT=$GOROOT_DIR GOCACHE=$OUT/go/.cache GOPATH=$OUT/go/.path GOTOOLCHAIN=local \
    GO111MODULE=off "$GOROOT_DIR/bin/go" build -o "$exe" "$src" \
    > "$exe.log" 2>&1 || { say "Go failed on $name: $exe.log"; return 1; }
  echo "$exe"
}

# ---- measurement -----------------------------------------------------------

# measure_best EXE INPUT TAG: runs EXE RUNS times on INPUT (a string) with
# an unlimited stack, and prints "<best seconds> <peak KiB>" (the peak is
# the largest of the runs). The output of the last run is left in
# $OUT/out/TAG. A run that fails makes the whole measurement fail.
measure_best() {
  exe=$1; input=$2; tag=$3
  mkdir -p "$OUT/out"
  printf '%s\n' "$input" > "$OUT/out/$tag.in"
  best=""; peak=0; i=0
  while [ "$i" -lt "$RUNS" ]; do
    i=$((i + 1))
    line=$( (ulimit -s unlimited 2>/dev/null; LEAN_STACK_SIZE_KB=4194304 \
             "$MEASURE" "$OUT/out/$tag.in" "$OUT/out/$tag.out" "$exe") 2>"$OUT/out/$tag.err") ||
      { say "$tag: cannot run $exe"; return 1; }
    set -- $line
    [ "$3" = 0 ] || { say "$tag: $exe exited with status $3 (see $OUT/out/$tag.err)"; return 1; }
    best=$(awk -v a="$best" -v b="$1" 'BEGIN { if (a == "" || b + 0 < a + 0) print b; else print a }')
    [ "$2" -gt "$peak" ] && peak=$2
  done
  echo "$best $peak"
}

# ---- the lowered programs (experiments 2 to 4) -------------------------------

# build_runtime VARIANT DEFINES...: the runtime prototype, compiled once per
# variant; prints the object's path.
build_runtime() {
  variant=$1; shift
  obj=$OUT/rt/runtime-$variant.o
  src=$ROOT/foreign/idr/bench/gate/runtime.cc
  fresh "$obj" "$src" "$ROOT/foreign/idr/bench/gate/runtime.h" && { echo "$obj"; return 0; }
  have_snmalloc || { say "snmalloc not found at $SNMALLOC_SRC (third_party/snmalloc)"; return 1; }
  mkdir -p "$OUT/rt"
  # snmalloc with size classes in 8-byte steps (plan 5.6).
  "$CXX" -std=c++20 -O2 -DNDEBUG -march=$CPU -mcx16 -pthread -fno-exceptions -fno-rtti \
    -DSNMALLOC_USE_WAIT_ON_ADDRESS=1 -DSNMALLOC_MIN_ALLOC_STEP_SIZE=8 "$@" \
    -I "$SNMALLOC_SRC" -c "$src" -o "$obj" > "$obj.log" 2>&1 ||
    { say "the runtime prototype failed to compile: $obj.log"; return 1; }
  echo "$obj"
}

# Runtime variants: the defines of each.
runtime_defines() {
  case $1 in
    plain) ;;
    stats) echo "-DIDR_GATE_STATS" ;;
    flush) echo "-DIDR_GATE_FLUSH" ;;
    home) echo "-DIDR_GATE_HOME" ;;
    flush-home) echo "-DIDR_GATE_FLUSH -DIDR_GATE_HOME" ;;
    *) say "gate: unknown runtime variant $1"; return 1 ;;
  esac
}

# lower EXE VARIANT FILE...: lowers a hand-written module (the prelude, then
# the FILEs) with the pinned LLVM's tools, as idris-mlir-cc's last steps do
# (OPT-PIPE-1 steps 9-11, with plan 5.7's O3, x86-64-v3 and internalizing
# every symbol but the entry), and links it with the runtime prototype.
lower() {
  exe=$1; variant=$2; shift 2
  have_llvm || { say "the pinned LLVM tools are missing from $LLVM_BIN"; return 1; }
  defines=$(runtime_defines "$variant") || return 1
  rt=$(build_runtime "$variant" $defines) || return 1
  work=$exe.work
  mkdir -p "$work"
  cat "$GATE/lowered/prelude.mlir" "$@" > "$work/module.mlir"
  "$LLVM_BIN/mlir-opt" \
    --pass-pipeline='builtin.module(canonicalize,cse,convert-scf-to-cf,convert-to-llvm,reconcile-unrealized-casts)' \
    "$work/module.mlir" -o "$work/llvm.mlir" &&
  "$LLVM_BIN/mlir-translate" --mlir-to-llvmir "$work/llvm.mlir" -o "$work/module.ll" &&
  "$LLVM_BIN/opt" -mtriple=$TRIPLE -mcpu=$CPU -internalize-public-api-list=idr_main \
    -passes='internalize,default<O3>' "$work/module.ll" -o "$work/module.bc" &&
  "$LLVM_BIN/llc" -O3 -mtriple=$TRIPLE -mcpu=$CPU -relocation-model=pic -filetype=obj \
    --align-all-functions=6 --align-all-nofallthru-blocks=6 "$work/module.bc" -o "$work/module.o" &&
  "$CXX" -pthread "$work/module.o" "$rt" -o "$exe" ||
    { say "lowering $* failed"; return 1; }
}

# The files of each lowered program in bench/gate/lowered, after the
# prelude.
lowered_files() {
  case $1 in
    rbtree) echo "rbmap.mlir rbtree.mlir" ;;
    deriv) echo "deriv.mlir" ;;
    binarytrees) echo "bintree.mlir binarytrees.mlir" ;;
    linrb-static) echo "linrb-static.mlir linrb.mlir" ;;
    linrb-dynamic) echo "linrb-dynamic.mlir linrb.mlir" ;;
    ptrees) echo "bintree.mlir ptrees.mlir" ;;
    shmap) echo "rbmap.mlir shmap.mlir" ;;
    pipe) echo "bintree.mlir pipe.mlir" ;;
    *) say "gate: no lowered program $1"; return 1 ;;
  esac
}

# build_lowered NAME [VARIANT]: a program of bench/gate/lowered, lowered and
# linked with a runtime variant; prints the executable's path.
build_lowered() {
  name=$1; variant=${2:-plain}
  files=$(lowered_files "$name") || return 1
  set --
  for f in $files; do set -- "$@" "$GATE/lowered/$f"; done
  exe=$OUT/lowered/$name-$variant
  mkdir -p "$OUT/lowered"
  fresh "$exe" "$@" "$GATE/lowered/prelude.mlir" "$ROOT/foreign/idr/bench/gate/runtime.cc" \
    "$ROOT/foreign/idr/bench/gate/runtime.h" && { echo "$exe"; return 0; }
  lower "$exe" "$variant" "$@" > "$exe.log" 2>&1 ||
    { say "lowering $name failed: $exe.log"; cat "$exe.log" >&2; return 1; }
  echo "$exe"
}
