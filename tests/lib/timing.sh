# Every compilation's wall time is recorded under tests/build/timing, one
# file per test, with the module it emitted; tests/compile-times.sh lists
# the slowest. The record gates nothing.

# now_ms: the wall clock in milliseconds (now_ns, tools/host.sh).
now_ms() {
  now_ms_ns=$(now_ns) || return 1
  say "$(( now_ms_ns / 1000000 ))"
}

# The timing record of this test: tests/build/timing/<test path, / as __>.tsv,
# one line per compilation, `<ms> TAB <exit> TAB <what> TAB <module>`, where
# <module> is the emitted .mlir kept next to it (or -), so that
# tests/compile-times.sh can run idris-mlir --mlir-timing on it again.
timing_dir=$root/tests/build/timing
case $here in
  "$root/tests/"*) timing_id=$(printf '%s' "${here#"$root/tests/"}" | sed 's|/|__|g') ;;
  *) timing_id=$(printf '%s' "$here" | sed 's|^/||; s|/|__|g') ;;
esac
timing_count=0

# record_time MS COMPILE-ARGUMENTS...: one line of the timing record. What
# was compiled is named by the options that change the compilation: not the
# packages, nor where the dumps go.
record_time() {
  record_ms=$1
  shift
  record_what=compile
  while [ $# -gt 2 ]; do
    case $1 in
      -p) shift ;;
      --dump-dir=*) ;;
      *) record_what="$record_what $1" ;;
    esac
    shift
  done
  record_source=$1
  record_output=$2
  mkdir -p "$timing_dir" 2> /dev/null || return 0
  if [ "$timing_count" -eq 0 ]; then
    : > "$timing_dir/$timing_id.tsv"
    rm -f "$timing_dir/$timing_id".*.mlir
  fi
  timing_count=$((timing_count + 1))
  record_module=-
  if [ "$compiled" -eq 0 ]; then
    record_dir=$(dirname "$record_source")
    record_found=$record_dir/build/exec/${record_output##*/}.mlir
    if [ -n "$record_found" ] && [ -f "$record_found" ]; then
      record_module=$timing_dir/$timing_id.$timing_count.mlir
      cp "$record_found" "$record_module" 2> /dev/null || record_module=-
    fi
  fi
  printf '%s\t%s\t%s\t%s\n' "$record_ms" "$compiled" "$record_what" "$record_module" \
    >> "$timing_dir/$timing_id.tsv"
}

# timing_rows REPORT: the rows of an execution time report (idris-mlir
# --mlir-timing, MLIR's tree display), in order, each as `<depth> TAB <seconds>
# TAB <name>`: depth 0 for a row of the report's own (the parse, a step of
# the pipeline, LLVM, Rest, Total), one more for each row it is nested in;
# seconds the wall time, the last `<seconds> (<percent>%)` of the line.
timing_rows() {
  awk '
    {
      rest = $0
      seconds = ""
      while (match(rest, /-?[0-9]+\.[0-9]+ \( *-?[0-9.]+%\)  /)) {
        split(substr(rest, RSTART, RLENGTH), pair, " ")
        seconds = pair[1]
        rest = substr(rest, RSTART + RLENGTH)
      }
      if (seconds == "") next
      match(rest, /^ */)
      printf "%d\t%s\t%s\n", RLENGTH / 2, seconds, substr(rest, RLENGTH + 1)
    }' "$1"
}
