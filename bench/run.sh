#!/bin/sh
# Runs the benchmarks (make bench): each program built by this compiler, by
# the stock Idris Chez backend (the same source), by MLton (bench/sml) and by
# the pinned clang -O2 (bench/c; static PIE on musl, as our programs), on the
# same input. Prints a Markdown table of the best
# of several wall-clock times, and checks that the outputs agree; then the
# wall-clock time this compiler took to compile each program.
#
#     bench/run.sh [--runs N] [name ...]
#
# MLton is looked up in .toolchain/mlton (the Debian package, unpacked there
# with dpkg -x) and then on PATH; a missing compiler is reported and skipped.
# Times come from GNU date's nanoseconds. The Idris environment is the
# Makefile's. Every build and run is killed after 300 seconds times
# IDRIS_MLIR_TIME_SCALE, and a benchmark that times out fails.

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"
bench=$root/bench
labels='this compiler|Idris Chez|MLton|clang -O2'

# The input of each benchmark: large enough that start-up does not matter.
input() {
  case $1 in
    nbody) echo 5000000 ;;
    mandelbrot) echo 2000 ;;
    fib) echo 38 ;;
    tak) echo 18 ;;
    collatz) echo 3000000 ;;
    ack) echo 10 ;;
    ackdyn) echo 10 ;;
    harmonic) echo 200000000 ;;
    *) return 1 ;;
  esac
}
all='nbody mandelbrot fib tak collatz ack ackdyn harmonic'

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
      idris_sources "$work/ours"
      compile_start=$(date +%s%N)
      bounded "$root/tools/compile.sh" --io "$work/ours/Main.idr" prog > "$work/build.log" 2>&1 &&
        cmd=$work/ours/build/exec/prog
      # The whole chain's wall time: idris-mlir, idris-mlir-cc and the link.
      echo "$name|$(( $(date +%s%N) - compile_start ))" >> "$compiles"
      ;;
    'Idris Chez')
      idris_sources "$work/chez"
      (cd "$work/chez" && bounded "$idris2" --no-banner --no-color --no-prelude --cg chez -o prog Main.idr) \
        > "$work/build.log" 2>&1 && cmd=$work/chez/build/exec/prog
      ;;
    MLton)
      if [ -z "$mlton" ]; then missing=yes; return; fi
      cat "$bench/sml/common.sml" "$bench/sml/$name.sml" > "$work/$name.sml"
      # Idris's Int is 64 bits; MLton's default int is 32.
      bounded "$mlton" -default-type int64 -output "$work/$name-mlton" "$work/$name.sml" \
        > "$work/build.log" 2>&1 && cmd=$work/$name-mlton
      ;;
    'clang -O2')
      bounded "$pinned_cc" -O2 "$bench/c/$name.c" -o "$work/$name-c" > "$work/build.log" 2>&1 &&
        cmd=$work/$name-c
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
    bounded "$1" < "$work/stdin" > "$2" 2> "$work/stderr"
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
  stdin=$(input "$name") || die "unknown benchmark: $name"
  work=$tmp/$name
  mkdir "$work"
  printf '%s' "$stdin" > "$work/stdin"
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
  [ -f "$reference" ] || die "$name: this compiler built nothing to compare with"
  for label; do
    out=$work/$label.out
    [ -f "$out" ] || continue
    if [ "$label" = 'Idris Chez' ] && ! cmp -s "$out" "$reference"; then
      die "$name: Chez printed $(cat "$out"), this compiler $(cat "$reference")"
    fi
    agree "$out" "$reference" ||
      die "$name: $label printed $(cat "$out"), this compiler $(cat "$reference")"
  done
  echo "$name|$stdin$times" >> "$rows"
done

cpus=$(getconf _NPROCESSORS_ONLN 2> /dev/null || nproc 2> /dev/null || echo 1)
echo "Best of $runs runs, wall-clock seconds; $(uname -m), $cpus CPUs. Outputs agree."
echo
echo "| benchmark | input | this compiler | Idris Chez | MLton | clang -O2 | vs MLton |"
echo "| --- | --- | ---: | ---: | ---: | ---: | ---: |"
awk -F'|' '
  function cell(t) { return t == "" ? "n/a" : sprintf("%.3f", t / 1e9) }
  {
    ratio = ($5 != "" && $3 != "" && $3 > 0) ? sprintf("%.2fx", $5 / $3) : "n/a"
    printf "| %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, cell($3), cell($4), cell($5), cell($6), ratio
  }' "$rows"
echo
echo "Compile time of this compiler, wall-clock seconds, once: idris-mlir, idris-mlir-cc and the link."
echo
echo "| benchmark | compile |"
echo "| --- | ---: |"
awk -F'|' '{ printf "| %s | %.3f |\n", $1, $2 / 1e9 }' "$compiles"
