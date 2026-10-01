#!/bin/sh
# Runs the benchmarks (make bench): each program built by this compiler, by
# the stock Idris Chez backend (the same source), by MLton (bench/sml), by
# the pinned clang -O2 (bench/c; static PIE on musl, as our programs), by
# Koka (bench/koka) and by Lean 4 (bench/lean), on the same input. clang
# compiles for the CPU this compiler targets (idris-mlir-cc
# --print-target-cpu), and without floating-point contraction, which this
# compiler never does:
# the columns compare compilers, not instruction sets or rounding. Prints a
# Markdown table of the best of several wall-clock times, and checks that
# the outputs agree; then the wall-clock time this compiler took to compile
# each program.
#
#     bench/run.sh [--runs N] [name ...]
#
# MLton is looked up in .toolchain/mlton (the Debian package, unpacked there
# with dpkg -x) and then on PATH; Koka and Lean in .toolchain/koka and
# .toolchain/lean (bench/toolchains.sh fetches them) and then on PATH. A
# missing compiler is reported and skipped.
# Times come from GNU date's nanoseconds. The Idris environment is the
# Makefile's. Every build and run is killed after 300 seconds times
# IDRIS_MLIR_TIME_SCALE, and a benchmark that times out fails.

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"
bench=$root/bench
labels='this compiler|Idris Chez|MLton|clang -O2|Koka|Lean 4'

# A benchmark is a directory bench/<name>/ holding Main.idr and one of
#   input       its stdin, given literally (a number, usually);
#   input-from  "<generator> <argument>": its stdin is what the C version of
#               the benchmark <generator> prints for <argument>, as the
#               benchmarks game feeds fasta's output to k-nucleotide;
# and optionally
#   compare     "bytes" when every output must equal the reference byte
#               for byte; otherwise they must print the same numbers;
#   libs        linker flags the C version needs (-lgmp);
#   packages    installed Idris packages the program uses (mlir-linear),
#               for this compiler and for Chez alike;
#   reference   the name of another benchmark whose C, SML, Koka and Lean
#               versions are this one's references (fannkuch-linear's is
#               fannkuch-redux);
#   rejected    the reason this compiler gives for rejecting the program
#               today; its column then reads n/a and the C version's output
#               is the reference;
#   differs     why this compiler's output differs from Chez's today (a
#               decided divergence); its column reads n/a likewise.
# The C, SML, Koka and Lean versions are bench/c/<name>.c,
# bench/sml/<name>.sml, bench/koka/<name>.kk and bench/lean/<name>.lean; a
# missing one is skipped. Every input is large enough that start-up does
# not matter.
all=$(cd "$bench" && for d in */; do [ -f "$d/Main.idr" ] && { [ -f "$d/input" ] || [ -f "$d/input-from" ]; } && echo "${d%/}"; done | LC_ALL=C sort | tr '\n' ' ')

die() {
  echo "$*" >&2
  exit 1
}

command -v timeout > /dev/null 2>&1 || die "no timeout command, so a benchmark could hang"
limit=$(( 300 * ${IDRIS_MLIR_TIME_SCALE:-1} ))

# bounded CMD...: CMD, killed after $limit seconds; a timeout exits 124.
bounded() {
  timeout -k 5 "$limit" "$@"
  bounded_status=$?
  case $bounded_status in
    124 | 137) echo "timed out after ${limit}s: ${1##*/}" >&2; return 124 ;;
  esac
  return "$bounded_status"
}

# The CPU is decided in one place, idris-mlir-cc, and clang is told it as
# LLVM's target CPU, which every target takes; the driver's spellings
# differ by architecture (-march on x86-64, -mcpu on arm64).
target_cpu=$("$idris_mlir_cc" --print-target-cpu) || die "idris-mlir-cc names no target CPU; run make build"

runs=5
names=
while [ $# -gt 0 ]; do
  case $1 in
    --runs) [ $# -ge 2 ] || die "usage: bench/run.sh [--runs N] [name ...]"; runs=$2; shift ;;
    --runs=*) runs=${1#--runs=} ;;
    -*) die "usage: bench/run.sh [--runs N] [name ...]" ;;
    *) names="$names $1" ;;
  esac
  shift
done
[ -n "$names" ] || names=$all
case $runs in
  '' | *[!0-9]*) die "--runs takes a number" ;;
esac

mlton=$toolchain/mlton/usr/bin/mlton
[ -f "$mlton" ] || mlton=$(command -v mlton 2> /dev/null)
koka=$toolchain/koka/bin/koka
[ -x "$koka" ] || koka=$(command -v koka 2> /dev/null)
lean=$toolchain/lean/bin/lean
leanc=$toolchain/lean/bin/leanc
if [ ! -x "$lean" ] || [ ! -x "$leanc" ]; then
  lean=$(command -v lean 2> /dev/null)
  leanc=$(command -v leanc 2> /dev/null)
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idris-mlir-bench.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM

# idris_sources DIR: the benchmark's Idris source, and bench/lib's, in DIR.
idris_sources() {
  mkdir "$1"
  for source in "$bench"/lib/*.idr "$bench/$name/Main.idr"; do
    [ -f "$source" ] && cp "$source" "$1/"
  done
}

# build LABEL: the command that runs the benchmark built one way, in $cmd,
# or nothing if that compiler is missing or failed; a failure is reported.
build() {
  cmd=
  missing=
  case $1 in
    'this compiler')
      if [ -f "$bench/$name/rejected" ] || [ -f "$bench/$name/differs" ]; then missing=yes; return; fi
      idris_sources "$work/ours"
      compile_start=$(date +%s%N)
      # shellcheck disable=SC2086 # the packages are words
      bounded "$root/tools/compile.sh" $packages "$work/ours/Main.idr" prog > "$work/build.log" 2>&1 &&
        cmd=$work/ours/build/exec/prog
      # The whole chain's wall time: idris-mlir, idris-mlir-cc and the link.
      echo "$name|$(( $(date +%s%N) - compile_start ))" >> "$compiles"
      ;;
    'Idris Chez')
      idris_sources "$work/chez"
      # shellcheck disable=SC2086 # the packages are words
      (cd "$work/chez" && bounded "$idris2" --no-banner --no-color --no-prelude $packages --cg chez -o prog Main.idr) \
        > "$work/build.log" 2>&1 && cmd=$work/chez/build/exec/prog
      ;;
    MLton)
      if [ -z "$mlton" ] || [ ! -f "$bench/sml/$reference.sml" ]; then missing=yes; return; fi
      cat "$bench/sml/common.sml" "$bench/sml/$reference.sml" > "$work/$name.sml"
      # Idris's Int is 64 bits; MLton's default int is 32.
      bounded "$mlton" -default-type int64 -output "$work/$name-mlton" "$work/$name.sml" \
        > "$work/build.log" 2>&1 && cmd=$work/$name-mlton
      ;;
    'clang -O2')
      if [ ! -f "$bench/c/$reference.c" ]; then missing=yes; return; fi
      libs=
      [ -f "$bench/$name/libs" ] && libs=$(cat "$bench/$name/libs")
      # shellcheck disable=SC2086 # libs holds linker flags, split on spaces
      bounded "$pinned_cc" -O2 -Xclang -target-cpu -Xclang "$target_cpu" -ffp-contract=off \
        "$bench/c/$reference.c" \
        -o "$work/$name-c" -lm $libs > "$work/build.log" 2>&1 &&
        cmd=$work/$name-c
      ;;
    Koka)
      if [ -z "$koka" ] || [ ! -f "$bench/koka/$reference.kk" ]; then missing=yes; return; fi
      mkdir "$work/koka"
      cp "$bench/koka/$reference.kk" "$work/koka/"
      # The Perceus benchmarks' flags: -O2 and a 128 MiB stack.
      (cd "$work/koka" && bounded "$koka" -O2 --stack=128M --builddir="$work/koka/build" \
         -o "$work/$name-koka" "$reference.kk") > "$work/build.log" 2>&1 && cmd=$work/$name-koka
      ;;
    'Lean 4')
      if [ -z "$lean" ] || [ -z "$leanc" ] || [ ! -f "$bench/lean/$reference.lean" ]; then missing=yes; return; fi
      # As Lean's own benchmarks: lean emits C, leanc -O3 -DNDEBUG compiles it.
      { bounded "$lean" -c "$work/$name-lean.c" "$bench/lean/$reference.lean" &&
        bounded "$leanc" -O3 -DNDEBUG -o "$work/$name-lean" "$work/$name-lean.c"; } \
        > "$work/build.log" 2>&1 && cmd=$work/$name-lean
      ;;
  esac
  if [ -z "$cmd" ] && [ -z "$missing" ]; then
    echo "$name: $1 failed to build:" >&2
    cat "$work/build.log" >&2
  fi
}

# timed CMD OUT: the best wall-clock time of $runs runs of CMD on the input,
# in nanoseconds, in $best; the last run's stdout in OUT.
timed() {
  best=
  run=0
  while [ "$run" -lt "$runs" ]; do
    start=$(date +%s%N)
    # With an unlimited stack, as Lean's and Koka's benchmarks run: cfold
    # and deriv recurse as deep as their input is large.
    (ulimit -s unlimited 2> /dev/null; bounded "$1" < "$work/stdin" > "$2" 2> "$work/stderr")
    status=$?
    end=$(date +%s%N)
    [ "$status" -eq 0 ] || die "$1 exited $status: $(cat "$work/stderr")"
    elapsed=$((end - start))
    if [ -z "$best" ] || [ "$elapsed" -lt "$best" ]; then best=$elapsed; fi
    run=$((run + 1))
  done
}

# agree A B: the two outputs print the same numbers, to 1e-9 (SML writes a
# minus sign as ~).
agree() {
  awk '
    function numbers(file, list,   line, n, count) {
      count = 0
      while ((getline line < file) > 0) {
        gsub(/~/, "-", line)
        while (match(line, /-?[0-9]+(\.[0-9]+)?([eE]-?[0-9]+)?/)) {
          list[++count] = substr(line, RSTART, RLENGTH) + 0
          line = substr(line, RSTART + RLENGTH)
        }
      }
      close(file)
      return count
    }
    function abs(x) { return x < 0 ? -x : x }
    BEGIN {
      n = numbers(ARGV[1], xs); m = numbers(ARGV[2], ys)
      if (n != m) exit 1
      for (i = 1; i <= n; i++)
        if (abs(xs[i] - ys[i]) > 1e-9 * (abs(xs[i]) > 1 ? abs(xs[i]) : 1)) exit 1
      exit 0
    }' "$1" "$2"
}

rows=$tmp/rows
: > "$rows"
compiles=$tmp/compiles
: > "$compiles"
for name in $names; do
  [ -f "$bench/$name/Main.idr" ] || die "unknown benchmark: $name"
  work=$tmp/$name
  mkdir "$work"
  packages=
  if [ -f "$bench/$name/packages" ]; then
    for package in $(cat "$bench/$name/packages"); do packages="$packages -p $package"; done
  fi
  reference=$name
  [ -f "$bench/$name/reference" ] && reference=$(cat "$bench/$name/reference")
  if [ -f "$bench/$name/input" ]; then
    stdin=$(cat "$bench/$name/input")
    printf '%s' "$stdin" > "$work/stdin"
  elif [ -f "$bench/$name/input-from" ]; then
    stdin=$(cat "$bench/$name/input-from")
    set -- $stdin
    bounded "$pinned_cc" -O2 "$bench/c/$1.c" -o "$work/generator" -lm ||
      die "$name: the generator $1 failed to build"
    printf '%s' "$2" | bounded "$work/generator" > "$work/stdin" ||
      die "$name: the generator $1 failed"
  else
    die "$name: no input or input-from"
  fi
  compare=numbers
  [ -f "$bench/$name/compare" ] && compare=$(cat "$bench/$name/compare")
  times=
  IFS='|'
  set -- $labels
  unset IFS
  for label; do
    build "$label"
    if [ -n "$cmd" ]; then
      timed "$cmd" "$work/$label.out"
      times="$times|$best"
    else
      times="$times|"
    fi
  done
  reference="$work/this compiler.out"
  [ -f "$reference" ] || reference="$work/clang -O2.out"
  [ -f "$reference" ] || die "$name: neither this compiler nor clang built anything to compare with"
  for label; do
    out=$work/$label.out
    [ -f "$out" ] || continue
    if { [ "$label" = 'Idris Chez' ] || [ "$compare" = bytes ]; } && ! cmp -s "$out" "$reference"; then
      die "$name: $label's output differs from the reference: $(cmp "$out" "$reference" | head -n 1)"
    fi
    agree "$out" "$reference" ||
      die "$name: $label printed $(head -c 200 "$out"), the reference $(head -c 200 "$reference")"
  done
  echo "$name|$stdin$times" >> "$rows"
done

cpus=$(getconf _NPROCESSORS_ONLN 2> /dev/null || nproc 2> /dev/null || echo 1)
echo "Best of $runs runs, wall-clock seconds; $(uname -m), $cpus CPUs. Outputs agree."
echo
echo "| benchmark | input | this compiler | Idris Chez | MLton | clang -O2 | Koka | Lean 4 | clang / this |"
echo "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
awk -F'|' '
  function cell(t) { return t == "" ? "n/a" : sprintf("%.3f", t / 1e9) }
  {
    ratio = ($6 != "" && $3 != "" && $3 > 0) ? sprintf("%.2fx", $6 / $3) : "n/a"
    printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, cell($3), cell($4), cell($5), cell($6), cell($7), cell($8), ratio
  }' "$rows"
echo
echo "Compile time of this compiler, wall-clock seconds, once: idris-mlir, idris-mlir-cc and the link."
echo
echo "| benchmark | compile |"
echo "| --- | ---: |"
awk -F'|' '{ printf "| %s | %.3f |\n", $1, $2 / 1e9 }' "$compiles"
