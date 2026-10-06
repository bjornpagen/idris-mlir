#!/bin/sh
# The compile times the golden tests recorded (tests/lib/timing.sh,
# `record_time`): the slowest compilations, each broken down by
# idris-mlir-cc's --timing into JIT compilation, evaluation and everything
# else; with --against, what slowed down since an earlier record. It
# reports; it gates nothing.
#
#     tests/compile-times.sh [--top N] [--no-breakdown] [--against OLD-DIR]
#                            [TIMING-DIR]
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
#
# --against OLD-DIR compares with the records of an earlier run (a copy of
# tests/build/timing taken before `make test` writes it again): a
# compilation of the same test, the same compilation of its run, in both.
# It prints the totals of those and the N whose time grew the most, by the
# ratio of the two, among those that took a second or more in either: a
# change that makes compilation grow faster than the program shows there
# first, on the largest programs. The times are wall times under the load
# of the run that recorded them, so compare runs made alike.

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"

usage() {
  echo "usage: $0 [--top N] [--no-breakdown] [--against OLD-DIR] [TIMING-DIR]" >&2
  exit 2
}
top=10
breakdown=yes
against=
dir=$root/tests/build/timing
while [ $# -gt 0 ]; do
  case $1 in
    --top) [ $# -ge 2 ] || usage; top=$2; shift ;;
    --no-breakdown) breakdown= ;;
    --against) [ $# -ge 2 ] || usage; against=$2; shift ;;
    -*) usage ;;
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
if [ -n "$against" ]; then
  set -- "$against"/*.tsv
  if [ ! -f "$1" ]; then
    echo "no timing records in $against" >&2
    exit 1
  fi
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idris-mlir-times.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM

# records DIR: every record in DIR, as `<ms> TAB <test> TAB <exit> TAB
# <what> TAB <module> TAB <n>`, the nth compilation of the test.
records() {
  for record in "$1"/*.tsv; do
    [ -f "$record" ] || continue
    test=${record##*/}
    test=$(printf '%s' "${test%.tsv}" | sed 's|__|/|g')
    awk -F'\t' -v test="$test" \
      'NF >= 4 { print $1 "\t" test "\t" $2 "\t" $3 "\t" $4 "\t" FNR }' "$record"
  done
}

# Every record, as `<ms> TAB <test> TAB <exit> TAB <what> TAB <module>`.
records "$dir" | cut -f 1-5 | sort -t "$(printf '\t')" -k1,1nr > "$tmp/all"

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

[ -n "$against" ] || exit 0
records "$against" > "$tmp/old"
records "$dir" > "$tmp/new"
# `<ratio> TAB <test> TAB <what> TAB <old ms> TAB <new ms>` for each
# compilation in both, the same compilation of the same test.
awk -F'\t' '
  NR == FNR { old[$2 "\t" $6] = $1; oldWhat[$2 "\t" $6] = $4; next }
  ($2 "\t" $6) in old && oldWhat[$2 "\t" $6] == $4 {
    o = old[$2 "\t" $6] + 0; n = $1 + 0
    printf "%.3f\t%s\t%s\t%d\t%d\n", (o > 0 ? n / o : 0), $2, $4, o, n
  }' "$tmp/old" "$tmp/new" > "$tmp/pairs"
echo
awk -F'\t' -v against="$against" '
  { o += $4; n += $5 }
  END {
    printf "Against %s: %d compilations in both, %.1f s then, %.1f s now (x%.2f).\n",
      against, NR, o / 1000, n / 1000, (o > 0 ? n / o : 0)
  }' "$tmp/pairs"
echo
echo "The $top that grew the most, of those that took a second or more:"
echo
echo "| test | compilation | then s | now s | now/then |"
echo "| --- | --- | ---: | ---: | ---: |"
awk -F'\t' '$4 >= 1000 || $5 >= 1000' "$tmp/pairs" | sort -t "$(printf '\t')" -k1,1nr |
  head -n "$top" | awk -F'\t' '{ printf "| %s | %s | %.3f | %.3f | %.2f |\n", $2, $3, $4 / 1000, $5 / 1000, $1 }'
