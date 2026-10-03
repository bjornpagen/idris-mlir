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
# tests/compile-times.sh can run idris-mlir-cc --timing on it again.
timing_dir=$root/tests/build/timing
case $here in
  "$root/tests/"*) timing_id=$(printf '%s' "${here#"$root/tests/"}" | sed 's|/|__|g') ;;
  *) timing_id=$(printf '%s' "$here" | sed 's|^/||; s|/|__|g') ;;
esac
timing_count=0

# record_time MS COMPILE-ARGUMENTS...: one line of the timing record.
record_time() {
  record_ms=$1
  shift
  record_what=compile
  while [ $# -gt 2 ]; do
    case $1 in
      --directive) record_what="$record_what --directive $2"; shift ;;
      -p) shift ;;
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
