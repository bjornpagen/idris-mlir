#!/bin/sh
# The compile times the golden tests recorded (tests/testutils.sh,
# `record_time`): the slowest compilations, each broken down by
# idris-mlir-cc's --timing into JIT compilation, evaluation and everything
# else. It reports; it gates nothing.
#
#     tests/compile-times.sh [--top N] [--no-breakdown] [TIMING-DIR]
#
# TIMING-DIR is tests/build/timing by default, where every run of `make
# test` (and of the other suites that compile) leaves one file per test:
# `<ms> TAB <exit> TAB <what> TAB <module>` per compilation, the module being
# the .mlir Emit wrote, kept so that it can be compiled again here.
#
# The breakdown compiles each of the N slowest modules again with
# `idris-mlir-cc MODULE -o OBJECT --timing` (and --no-eval if the recorded
# compilation had it), and reads MLIR's execution time report: a row is
# `<seconds> (<percent>%) <name>`, and with several columns the last is the
# wall time. Rows whose name contains "JIT" (any case) are JIT compilation;
# rows whose name contains "evaluat" are evaluation (idr-eval's child
# running the calls); the rest of the total is everything else: parsing, the
# other passes, LLVM and the object file. The names are those idr-eval gives
# its nested timers; a report without such rows shows n/a. The wall time of
# the whole compilation (the frontend, idris-mlir-cc and the link) is the
# recorded one.

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"

top=10
breakdown=yes
dir=$root/tests/build/timing
while [ $# -gt 0 ]; do
  case $1 in
    --top) [ $# -ge 2 ] || { echo "usage: $0 [--top N] [--no-breakdown] [TIMING-DIR]" >&2; exit 2; }; top=$2; shift ;;
    --no-breakdown) breakdown= ;;
    -*) echo "usage: $0 [--top N] [--no-breakdown] [TIMING-DIR]" >&2; exit 2 ;;
    *) dir=$1 ;;
  esac
  shift
done
case $top in
  '' | *[!0-9]*) echo "--top takes a number" >&2; exit 2 ;;
esac

set -- "$dir"/*.tsv
if [ ! -f "$1" ]; then
  echo "no timing records in $dir: run make test first" >&2
  exit 1
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idris-mlir-times.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM

# Every record, as `<ms> TAB <test> TAB <exit> TAB <what> TAB <module>`.
for record in "$dir"/*.tsv; do
  test=${record##*/}
  test=$(printf '%s' "${test%.tsv}" | sed 's|__|/|g')
  awk -F'\t' -v test="$test" 'NF >= 4 { print $1 "\t" test "\t" $2 "\t" $3 "\t" $4 }' "$record"
done | sort -t "$(printf '\t')" -k1,1nr > "$tmp/all"

count=$(wc -l < "$tmp/all" | tr -d ' ')
total=$(awk -F'\t' '{ s += $1 } END { printf "%.1f", s / 1000 }' "$tmp/all")
echo "$count compilations recorded in $dir, $total s in all."
echo

# timing MODULE WHAT: idris-mlir-cc's report on MODULE, as
# `<total> <jit> <eval>` in seconds, or nothing.
timing() {
  timing_flags=--timing
  case $2 in *no-eval*) timing_flags="$timing_flags --no-eval" ;; esac
  # shellcheck disable=SC2086 # the flags are words
  "$idris_mlir_cc" "$1" -o "$tmp/object.o" $timing_flags > "$tmp/timing.out" 2> "$tmp/timing.err" || return 0
  cat "$tmp/timing.out" "$tmp/timing.err" | awk '
    /Total Execution Time:/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9.]+$/) total = $i }
    {
      line = $0; seconds = ""; name = ""
      # The last `<seconds> (<percent>%)` pair on the line is the wall time.
      while (match(line, /[0-9]+\.[0-9]+ \( *[0-9.]+%\)/)) {
        pair = substr(line, RSTART, RLENGTH)
        split(pair, parts, " ")
        seconds = parts[1]
        line = substr(line, RSTART + RLENGTH)
        name = line
      }
      if (seconds == "") next
      sub(/^[ \t]+/, "", name)
      lower = tolower(name)
      if (lower == "total") { if (total == "") total = seconds; next }
      if (lower ~ /jit/) jit += seconds
      else if (lower ~ /evaluat/) evaluation += seconds
      rows++
    }
    END {
      if (total == "") exit
      printf "%s %s %s %s\n", total, (rows ? jit + 0 : ""), (rows ? evaluation + 0 : ""), (jit + evaluation > 0 ? "yes" : "no")
    }'
}

echo "The $top slowest:"
echo
if [ -n "$breakdown" ]; then
  echo "| test | compilation | exit | wall s | idris-mlir-cc s | JIT compilation s | evaluation s | everything else s |"
  echo "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |"
else
  echo "| test | compilation | exit | wall s |"
  echo "| --- | --- | ---: | ---: |"
fi
head -n "$top" "$tmp/all" | while IFS="$(printf '\t')" read -r ms test status what module; do
  wall=$(awk -v ms="$ms" 'BEGIN { printf "%.3f", ms / 1000 }')
  if [ -z "$breakdown" ]; then
    echo "| $test | $what | $status | $wall |"
    continue
  fi
  cc=n/a; jit=n/a; evaluation=n/a; rest=n/a
  if [ "$module" != - ] && [ -f "$module" ] && [ -x "$idris_mlir_cc" ]; then
    report=$(timing "$module" "$what")
    if [ -n "$report" ]; then
      set -- $report
      cc=$1
      if [ "$4" = yes ]; then
        jit=$2
        evaluation=$3
        rest=$(awk -v t="$1" -v j="$2" -v e="$3" 'BEGIN { printf "%.4f", t - j - e }')
      fi
    fi
  fi
  echo "| $test | $what | $status | $wall | $cc | $jit | $evaluation | $rest |"
done
