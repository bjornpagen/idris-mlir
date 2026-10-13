# Determinism: the same program compiles to the same bytes: two
# compilations, byte for byte; and one module through the pipeline under one
# thread and under MLIR's pool.

# determinism FIXTURE: two compilations of the fixture, an IO program in
# Main.idr with the installed packages its `packages` names, give
# byte-identical .core, .mlir, object and executable, and dump the same
# module after every step of the pipeline.
determinism() {
  mkdir "$work/det"
  copy_fixture "$1" "$work/det"
  det_packages=
  if [ -f "$1/packages" ]; then
    for det_package in $(cat "$1/packages"); do det_packages="$det_packages -p $det_package"; done
  fi
  for det_round in 1 2; do
    rm -rf "$work/det/build"
    # shellcheck disable=SC2086 # the packages are words
    compile_program $det_packages --dump-dir="$work/det/build/exec/prog.dump" "$work/det/Main.idr" prog
    det_core=$work/det/build/exec/prog.core
    det_mlir=$work/det/build/exec/prog.mlir
    det_object=$work/det/build/exec/prog.o
    det_executable=$work/det/build/exec/prog
    det_dumps=$work/det/build/exec/prog.dump
    say "compile $det_round: exit $compiled"
    if [ "$compiled" -ne 0 ]; then
      show "$work/compile.out" "$work/compile.err"
      return
    fi
    mkdir "$work/round$det_round" "$work/round$det_round/dumps"
    cp "$det_core" "$work/round$det_round/core" 2> /dev/null
    cp "$det_mlir" "$work/round$det_round/mlir" 2> /dev/null
    cp "$det_object" "$work/round$det_round/object" 2> /dev/null
    cp "$det_executable" "$work/round$det_round/executable" 2> /dev/null
    cp "$det_dumps"/[0-9]*-*.mlir "$work/round$det_round/dumps/" 2> /dev/null
  done
  for det_kind in core mlir object executable; do
    if [ ! -f "$work/round1/$det_kind" ] || [ ! -f "$work/round2/$det_kind" ]; then
      say "$det_kind: missing"
    elif cmp -s "$work/round1/$det_kind" "$work/round2/$det_kind"; then
      say "$det_kind: identical"
    else
      say "$det_kind: differs between two compilations"
    fi
  done
  det_differ=
  det_count=0
  for det_name in $( (ls "$work/round1/dumps"; ls "$work/round2/dumps") | sort -u); do
    det_count=$((det_count + 1))
    cmp -s "$work/round1/dumps/$det_name" "$work/round2/dumps/$det_name" || det_differ="$det_differ $det_name"
  done
  if [ "$det_count" -eq 0 ]; then
    say "dumps: none"
  elif [ -n "$det_differ" ]; then
    say "dumps: differ between two compilations:$det_differ"
  else
    say "dumps: identical after every step"
  fi
}

# determinism_threads FIXTURE: the fixture's contract module through
# idris-mlir-opt's idr-pipeline under one thread and under MLIR's pool, and
# under the pool again: the same module, byte for byte with its locations,
# the same statistics, and the same remarks of the function passes that
# emit them (idr-vectorize and idr-narrow-lanes, through the diagnostic
# engine, which orders what a pass says of each function by the function,
# whichever thread ran it). With threading on, MLIR hands a nested
# pipeline's work to the pool's threads even when the pool has one, so
# per-thread state shows on any host. The remarks print as they are
# emitted and the statistics when the pipeline ends, after its last remark,
# from the report's first `===` line on.
determinism_threads() {
  mkdir "$work/det"
  copy_fixture "$1" "$work/det"
  det_packages=
  if [ -f "$1/packages" ]; then
    for det_package in $(cat "$1/packages"); do det_packages="$det_packages -p $det_package"; done
  fi
  # shellcheck disable=SC2086 # the packages are words
  compile_program $det_packages --dump-dir="$work/det/build/exec/prog.dump" "$work/det/Main.idr" prog
  say "compile: exit $compiled"
  if [ "$compiled" -ne 0 ]; then
    show "$work/compile.out" "$work/compile.err"
    return
  fi
  det_input=$work/det/build/exec/prog.mlir
  for det_run in one many again; do
    det_flags=
    [ "$det_run" = one ] && det_flags=--mlir-disable-threading
    # shellcheck disable=SC2086 # empty or one flag
    if ! bounded "$idris_mlir_opt" $det_flags --mlir-print-debuginfo --mlir-pass-statistics \
        --mlir-pass-statistics-display=list --remarks-filter=idr-vectorize,idr-narrow-lanes \
        --idr-target --idr-pipeline "$det_input" \
        -o "$work/$det_run.mlir" 2> "$work/$det_run.err"; then
      say "$det_run: exit $bounded_status"
      show "$work/$det_run.err"
      return
    fi
    awk 'stats || /^===/ { stats = 1; print > stats_file; next } { print }' \
      stats_file="$work/$det_run.stats" "$work/$det_run.err" > "$work/$det_run.remarks"
    [ -f "$work/$det_run.stats" ] || : > "$work/$det_run.stats"
  done
  if cmp -s "$work/one.mlir" "$work/many.mlir"; then
    say "module: identical under one thread and under many"
  else
    say "module: differs between one thread and many"
  fi
  if cmp -s "$work/many.mlir" "$work/again.mlir"; then
    say "module: identical under many, again"
  else
    say "module: differs between two runs under many"
  fi
  if cmp -s "$work/one.stats" "$work/many.stats"; then
    say "statistics: identical under one thread and under many"
  else
    say "statistics: differ between one thread and many"
  fi
  if cmp -s "$work/one.remarks" "$work/many.remarks"; then
    say "remarks: identical under one thread and under many"
  else
    say "remarks: differ between one thread and many"
    diff "$work/one.remarks" "$work/many.remarks" | head -n 20 | sed 's/^/  | /'
  fi
}
