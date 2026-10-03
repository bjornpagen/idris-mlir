#!/bin/sh
# Runs the benchmarks (make bench): each program built by this compiler, by
# the stock Idris Chez backend (the same source), by MLton (bench/sml), by
# the pinned clang -O2 (bench/c; linked as our programs are, with the flags
# idris-mlir-cc --print-link-flags names for the target), by Koka
# (bench/koka) and by Lean 4 (bench/lean), on the same input. clang
# compiles for the CPU this compiler targets (idris-mlir-cc
# --print-target-cpu), and without floating-point contraction, which this
# compiler never does:
# the columns compare compilers, not instruction sets or rounding. Prints
# what it ran on (the host, its CPU, the stack limit and every compiler's
# version) on stderr, checks that the outputs agree, and then prints
# bench/report.sh's results: the best of several wall-clock times per
# compiler and the wall-clock time this compiler took to compile each
# program.
#
#     bench/run.sh [--runs N] [--record DIR] [name ...]
#
# With --record, the run's record (every timed run, the compile times and
# what it ran on; bench/report.sh describes it) is kept in DIR, with the
# results and charts made from it, once every output has agreed: a run
# that fails leaves no record.
#
# MLton, Koka and Lean are looked up in .toolchain/mlton, .toolchain/koka
# and .toolchain/lean (bench/toolchains.sh puts them there) and then on
# PATH. A missing compiler is reported in the header and its column reads
# n/a. Times come from now_ns (tools/host.sh). Every program runs with the
# largest stack the system allows (stack_max: unlimited on Linux, the hard
# limit of about 64 MiB on macOS). The Idris environment is the Makefile's,
# set here too, so that a direct run builds against this checkout's libs/
# (`make build` makes its prefix). Every build and run is killed after 300
# seconds times IDRIS_MLIR_TIME_SCALE, and a benchmark that times out
# fails.

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"
unset IDRIS2_PATH IDRIS2_PACKAGE_PATH IDRIS2_INC_CGS IDRIS2_INC_SRC IDRIS2_DATA IDRIS2_LIBS IDRIS2_CG IDRIS2_BOOT
export IDRIS2_PREFIX="$checkout_prefix"
if [ -z "${CHEZ-}" ]; then
  CHEZ=$(stamp_field "$idris_prefix" scheme)
  [ -z "$CHEZ" ] || export CHEZ
fi
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

[ -n "$timeout_cmd" ] || die "$timeout_missing, so a benchmark could hang"
now_ns > /dev/null || die "no clock to time the benchmarks with"
limit=$(( 300 * ${IDRIS_MLIR_TIME_SCALE:-1} ))

# bounded CMD...: CMD, killed after $limit seconds; a timeout exits 124.
bounded() {
  "$timeout_cmd" -k 5 "$limit" "$@"
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
target_triple=$("$idris_mlir_cc" --print-target-triple) || die "idris-mlir-cc names no target triple; run make build"
# How the target links a program (a static PIE on musl, a dynamic
# executable on Darwin) is decided there too; the C programs and the input
# generators are linked so, as this compiler's programs are.
link_flags=$("$idris_mlir_cc" --print-link-flags) ||
  die "idris-mlir-cc --print-link-flags names no link flags for the target; run make build"
# The stack every program runs with: as large as the system allows.
stack=$(stack_max && ulimit -s) || die "cannot raise the stack limit"

runs=5
keep=
names=
while [ $# -gt 0 ]; do
  case $1 in
    --runs) [ $# -ge 2 ] || die "usage: bench/run.sh [--runs N] [--record DIR] [name ...]"; runs=$2; shift ;;
    --runs=*) runs=${1#--runs=} ;;
    --record) [ $# -ge 2 ] || die "usage: bench/run.sh [--runs N] [--record DIR] [name ...]"; keep=$2; shift ;;
    --record=*) keep=${1#--record=} ;;
    -*) die "usage: bench/run.sh [--runs N] [--record DIR] [name ...]" ;;
    *) names="$names $1" ;;
  esac
  shift
done
[ -n "$names" ] || names=$all
case $runs in
  '' | *[!0-9]*) die "--runs takes a number" ;;
esac
if [ -n "$keep" ] && [ -e "$keep" ] && [ -n "$(ls -A "$keep" 2> /dev/null)" ]; then
  die "--record $keep: not an empty directory; a record is never overwritten"
fi

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
record=$tmp/record
mkdir "$record"
: > "$record/samples.tsv"
: > "$record/compile.tsv"

# What the run measured on, first, so that its record describes itself:
# when and at which revision, the host, its CPU, the stack and each
# column's compiler, or why it reads n/a.
first_line() {
  "$@" 2>&1 | head -n 1
}
revision=$(git -C "$root" describe --always --dirty 2> /dev/null) || revision=unknown
{
  echo "Measured on $(date -u '+%Y-%m-%d at %H:%M UTC'), at $revision."
  echo
  echo "Host: $(uname -srm), $(cpu_name), $(getconf _NPROCESSORS_ONLN 2> /dev/null || echo 1) CPUs."
  case $stack in
    unlimited) echo "Stack: unlimited (ulimit -s), the most this system allows." ;;
    *) echo "Stack: $stack KiB (ulimit -s), the most this system allows." ;;
  esac
  echo
  echo "- this compiler: $revision, for $target_triple, CPU $target_cpu; link flags: $(printf "%s" "$link_flags" | tr "\n" " ")"
  echo "- Idris Chez: $(first_line "$idris2" --version); Chez Scheme $(first_line "${CHEZ:-scheme}" --version)"
  if [ -n "$mlton" ]; then
    echo "- MLton: $(first_line "$mlton")"
  else
    echo "- MLton: not found (bench/toolchains.sh mlton, or mlton on PATH); its column reads n/a"
  fi
  echo "- clang -O2: $(first_line "$pinned_cc" --version)"
  if [ -n "$koka" ]; then
    echo "- Koka: $(first_line "$koka" --version)"
  else
    echo "- Koka: not found (bench/toolchains.sh koka, or koka on PATH); its column reads n/a"
  fi
  if [ -n "$lean" ] && [ -n "$leanc" ]; then
    echo "- Lean 4: $(first_line "$lean" --version)"
  else
    echo "- Lean 4: not found (bench/toolchains.sh lean, or lean and leanc on PATH); its column reads n/a"
  fi
} > "$record/about"
cat "$record/about" >&2

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
      compile_start=$(now_ns)
      # shellcheck disable=SC2086 # the packages are words
      bounded "$root/tools/compile.sh" $packages "$work/ours/Main.idr" prog > "$work/build.log" 2>&1 &&
        cmd=$work/ours/build/exec/prog
      # The whole chain's wall time: idris-mlir, idris-mlir-cc and the link.
      printf '%s\t%s\n' "$name" "$(( $(now_ns) - compile_start ))" >> "$record/compile.tsv"
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
      # shellcheck disable=SC2086 # libs and link_flags hold flags, split on spaces
      bounded "$pinned_cc" -O2 -Xclang -target-cpu -Xclang "$target_cpu" -ffp-contract=off \
        "$bench/c/$reference.c" \
        -o "$work/$name-c" $link_flags -lm $libs > "$work/build.log" 2>&1 &&
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

# timed CMD OUT: $runs runs of CMD on the input, each one's wall-clock time
# a sample of the record; the last run's stdout in OUT.
timed() {
  run=0
  while [ "$run" -lt "$runs" ]; do
    start=$(now_ns)
    # With the largest stack there is, as Lean's and Koka's benchmarks run
    # (unlimited). Only cfold needs a deep one: its C program between 48
    # and 56 MiB on x86-64, under macOS's 64 MiB cap; its Koka program asks
    # for 128 MiB, which Koka takes with setrlimit on Linux (so a hard limit
    # below that fails it) and with a link flag on macOS.
    (ulimit -s "$stack" && bounded "$1" < "$work/stdin" > "$2" 2> "$work/stderr")
    status=$?
    end=$(now_ns)
    [ "$status" -eq 0 ] || die "$1 exited $status: $(cat "$work/stderr")"
    printf '%s\t%s\t%s\t%s\n' "$name" "$stdin" "$label" "$((end - start))" >> "$record/samples.tsv"
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
    # shellcheck disable=SC2086 # link_flags holds flags, split on spaces
    bounded "$pinned_cc" -O2 "$bench/c/$1.c" -o "$work/generator" $link_flags -lm ||
      die "$name: the generator $1 failed to build"
    printf '%s' "$2" | bounded "$work/generator" > "$work/stdin" ||
      die "$name: the generator $1 failed"
  else
    die "$name: no input or input-from"
  fi
  compare=numbers
  [ -f "$bench/$name/compare" ] && compare=$(cat "$bench/$name/compare")
  echo "$name" >&2
  IFS='|'
  set -- $labels
  unset IFS
  for label; do
    build "$label"
    [ -z "$cmd" ] || timed "$cmd" "$work/$label.out"
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
done

# Every output agreed: the record is complete, and what it shows is
# bench/report.sh's.
sh "$bench/report.sh" "$record" > /dev/null || die "bench/report.sh failed on the record"
if [ -n "$keep" ]; then
  mkdir -p "$keep" && cp "$record"/* "$keep"/ || die "cannot keep the record in $keep"
fi
cat "$record/results.md"
