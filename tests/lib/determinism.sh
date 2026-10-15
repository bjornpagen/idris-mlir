# Determinism: the same program compiles to the same bytes whatever the
# number of threads: one compilation at each of 1, 2 and 8 threads, byte
# for byte; and one module through the pipeline under one thread and under
# MLIR's pool.

# The thread counts every determinism check compiles at.
determinism_threads_counts='1 2 8'

# determinism FIXTURE: an IO program in Main.idr with the installed
# packages its `packages` names, compiled at each of 1, 2 and 8 threads,
# gives byte-identical artifacts of every kind (lib/compile.sh) and the
# same module after every step of the pipeline. --num-threads comes after
# the one tools/compile.sh passes, so it is the one that counts. Every
# compilation runs in the one directory, so nothing differs by where it
# ran, and its build is moved aside to $work/det<threads> after it.
determinism() {
  det_packages=
  if [ -f "$1/packages" ]; then
    for det_package in $(cat "$1/packages"); do det_packages="$det_packages -p $det_package"; done
  fi
  mkdir "$work/det"
  copy_fixture "$1" "$work/det"
  for det_threads in $determinism_threads_counts; do
    rm -rf "$work/det/build"
    # shellcheck disable=SC2046,SC2086 # the packages and the dump options are words
    compile_program $det_packages --num-threads="$det_threads" \
      $(dump_options "$work/det/build/exec/prog.dump") "$work/det/Main.idr" prog
    if [ "$det_threads" -eq 1 ]; then
      say "compile at 1 thread: exit $compiled"
    else
      say "compile at $det_threads threads: exit $compiled"
    fi
    if [ "$compiled" -ne 0 ]; then
      show "$work/compile.out" "$work/compile.err"
      return
    fi
    mkdir "$work/det$det_threads"
    mv "$work/det/build" "$work/det$det_threads/build"
  done
  for det_kind in $artifact_kinds; do
    det_differ=
    det_missing=
    for det_threads in $determinism_threads_counts; do
      artifact_files "$work/det$det_threads" prog "$det_kind" > "$work/files$det_threads"
      [ -s "$work/files$det_threads" ] || det_missing=yes
      sed "s|^$work/det$det_threads/||" "$work/files$det_threads" > "$work/names$det_threads"
    done
    if [ -n "$det_missing" ]; then
      say "$det_kind: missing"
      continue
    fi
    for det_threads in $determinism_threads_counts; do
      cmp -s "$work/names1" "$work/names$det_threads" || det_differ=yes
      while IFS= read -r det_name; do
        cmp -s "$work/det1/$det_name" "$work/det$det_threads/$det_name" || det_differ=yes
      done < "$work/names1"
    done
    if [ -n "$det_differ" ]; then
      say "$det_kind: differs between 1, 2 and 8 threads"
    else
      say "$det_kind: identical at 1, 2 and 8 threads"
    fi
  done
  det_differ=
  for det_threads in $determinism_threads_counts; do
    step_dumps "$work/det$det_threads/build/exec/prog.dump" > "$work/dumps$det_threads"
    sed 's|^.*/||' "$work/dumps$det_threads" > "$work/steps$det_threads"
  done
  det_count=$(wc -l < "$work/dumps1" | tr -d ' ')
  for det_threads in $determinism_threads_counts; do
    cmp -s "$work/steps1" "$work/steps$det_threads" || det_differ="$det_differ (the steps)"
    paste "$work/dumps1" "$work/dumps$det_threads" > "$work/pairs"
    while IFS="$(printf '\t')" read -r det_one det_other; do
      cmp -s "$det_one" "$det_other" || det_differ="$det_differ ${det_one##*/}"
    done < "$work/pairs"
  done
  if [ "$det_count" -eq 0 ]; then
    say "dumps: none"
  elif [ -n "$det_differ" ]; then
    say "dumps: differ between 1, 2 and 8 threads:$det_differ"
  else
    say "dumps: identical at 1, 2 and 8 threads"
  fi
}

# determinism_threads FIXTURE: the module the fixture's program hands the
# driver, through idris-mlir-opt's idr-pipeline under one thread and under
# MLIR's pool, and under the pool again: the same module, byte for byte
# with its locations, the same statistics, and the same remarks of the
# function pass that emits them (idr-narrow-lanes, through the diagnostic
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
  compile_program $det_packages "$work/det/Main.idr" prog
  say "compile: exit $compiled"
  if [ "$compiled" -ne 0 ]; then
    show "$work/compile.out" "$work/compile.err"
    return
  fi
  det_input=$(artifact_file "$work/det" prog module)
  for det_run in one many again; do
    det_flags=
    [ "$det_run" = one ] && det_flags=--mlir-disable-threading
    # shellcheck disable=SC2086 # empty or one flag
    if ! bounded "$idris_mlir_opt" $det_flags --mlir-print-debuginfo --mlir-pass-statistics \
        --mlir-pass-statistics-display=list --remarks-filter=idr-narrow-lanes \
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
