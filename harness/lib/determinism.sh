# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Determinism: the same program compiles to the same bytes whatever the
# number of threads: one compilation at each of 1, 3, 5 and 13 threads, one
# at a count drawn for the run, and one more at 13 in a second process,
# byte for byte; each executable they made gives the same bytes on every
# input; and one module through the pipeline under one thread and under
# MLIR's pool.

# The compilations every determinism check makes, by their thread counts:
# 1 runs serially; 3, 5 and 13 are pairwise coprime, so no two of them
# split a list of work at the same boundaries, and 13 is more threads than
# a small program has functions, so some threads get none; the last, 13
# again, is a second process, so nothing a process draws when it starts
# (where its allocator places things) reaches an artifact. Beside them, a
# count from 2 to 31 drawn from the clock (determinism_seed, which a
# failure names, and which IDRIS_MLIR_DETERMINISM_SEED replays), so that
# over many runs every split of the work is tried.
determinism_seed=${IDRIS_MLIR_DETERMINISM_SEED:-$(date +%s)}
determinism_drawn=$((2 + determinism_seed % 30))
case $determinism_drawn in 3 | 5 | 13) determinism_drawn=$((determinism_drawn + 1)) ;; esac
determinism_runs="1 3 5 13 $determinism_drawn 13"
# The same compilations in words, as the transcripts name them, the same
# whatever count was drawn.
determinism_phrase='1, 3, 5 and 13 threads, a drawn count and in a second process'

# determinism FIXTURE [INPUT...]: an IO program in Main.idr with the
# installed packages its `packages` names, compiled by each of
# determinism_runs, gives byte-identical artifacts of every kind
# (lib/compile.sh) and the same module after every step of the pipeline;
# and the executable of every compilation, each run in a process of its
# own, prints the same bytes and exits alike on every input: the stdin of
# each of the fixture's cases, the empty input, and each INPUT, a line
# written to stdin. --num-threads comes after
# the one tools/compile.sh passes, so it is the one that counts. Every
# compilation runs in the one directory, so nothing differs by where it
# ran, and its build is moved aside to $work/det<n> after it, n counting
# the compilations.
determinism() {
  det_packages=$(package_options "$1")
  mkdir "$work/det"
  copy_fixture "$1" "$work/det"
  det_run=0
  det_seen=
  det_runs=
  for det_threads in $determinism_runs; do
    det_run=$((det_run + 1))
    rm -rf "$work/det/build"
    # shellcheck disable=SC2046,SC2086 # the packages and the dump options are words
    compile_program $det_packages --num-threads="$det_threads" \
      $(dump_options "$work/det/build/exec/prog.dump") "$work/det/Main.idr" prog
    if [ "$det_threads" -eq 1 ]; then det_what="1 thread"; else det_what="$det_threads threads"; fi
    [ "$det_run" -eq 5 ] && det_what="a drawn count of threads"
    case " $det_seen " in *" $det_threads "*) det_what="$det_what, a second process" ;; esac
    det_seen="$det_seen $det_threads"
    say "compile at $det_what: exit $compiled"
    if [ "$compiled" -ne 0 ]; then
      [ "$det_run" -eq 5 ] && say "  the drawn count: $det_threads threads (IDRIS_MLIR_DETERMINISM_SEED=$determinism_seed)"
      show "$work/compile.out" "$work/compile.err"
      return
    fi
    mkdir "$work/det$det_run"
    mv "$work/det/build" "$work/det$det_run/build"
    det_runs="$det_runs $det_run"
  done
  for det_kind in $artifact_kinds; do
    det_differ=
    det_missing=
    for det_run in $det_runs; do
      artifact_files "$work/det$det_run" prog "$det_kind" > "$work/files$det_run"
      [ -s "$work/files$det_run" ] || det_missing=yes
      sed "s|^$work/det$det_run/||" "$work/files$det_run" > "$work/names$det_run"
    done
    if [ -n "$det_missing" ]; then
      say "$det_kind: missing"
      continue
    fi
    for det_run in $det_runs; do
      cmp -s "$work/names1" "$work/names$det_run" || det_differ=yes
      while IFS= read -r det_name; do
        cmp -s "$work/det1/$det_name" "$work/det$det_run/$det_name" || det_differ=yes
      done < "$work/names1"
    done
    if [ -n "$det_differ" ]; then
      say "$det_kind: differs at $determinism_phrase"
      say "  the drawn count: $determinism_drawn threads (IDRIS_MLIR_DETERMINISM_SEED=$determinism_seed)"
    else
      say "$det_kind: identical at $determinism_phrase"
    fi
  done
  det_differ=
  for det_run in $det_runs; do
    step_dumps "$work/det$det_run/build/exec/prog.dump" > "$work/dumps$det_run"
    sed 's|^.*/||' "$work/dumps$det_run" > "$work/steps$det_run"
  done
  det_count=$(wc -l < "$work/dumps1" | tr -d ' ')
  for det_run in $det_runs; do
    cmp -s "$work/steps1" "$work/steps$det_run" || det_differ="$det_differ (the steps)"
    paste "$work/dumps1" "$work/dumps$det_run" > "$work/pairs"
    while IFS="$(printf '\t')" read -r det_one det_other; do
      cmp -s "$det_one" "$det_other" || det_differ="$det_differ ${det_one##*/}"
    done < "$work/pairs"
  done
  if [ "$det_count" -eq 0 ]; then
    say "dumps: none"
  elif [ -n "$det_differ" ]; then
    say "dumps: differ at $determinism_phrase:$det_differ"
    say "  the drawn count: $determinism_drawn threads (IDRIS_MLIR_DETERMINISM_SEED=$determinism_seed)"
  else
    say "dumps: identical at $determinism_phrase"
  fi
  # The runs: each input, to each compilation's executable.
  det_fixture=$1
  shift
  mkdir "$work/inputs"
  : > "$work/inputs/empty"
  for det_case in "$det_fixture"/cases/*/; do
    [ -f "$det_case/stdin" ] && cp "$det_case/stdin" "$work/inputs/case-$(basename "$det_case")"
  done
  det_n=0
  for det_input in "$@"; do
    det_n=$((det_n + 1))
    printf '%s\n' "$det_input" > "$work/inputs/given-$det_n"
  done
  det_differ=
  for det_input in "$work"/inputs/*; do
    det_first=
    for det_run in $det_runs; do
      run_program "run$det_run" "$(artifact_file "$work/det$det_run" prog executable)" "$det_input"
      printf '%s\n' "$ran" > "$work/run$det_run.status"
      if [ -z "$det_first" ]; then
        det_first=$det_run
      elif ! cmp -s "$work/run$det_first.out" "$work/run$det_run.out" ||
           ! cmp -s "$work/run$det_first.status" "$work/run$det_run.status"; then
        det_differ="$det_differ ${det_input##*/} (compilation $det_run)"
      fi
    done
  done
  if [ -n "$det_differ" ]; then
    say "runs: the executables differ in what they print or how they exit on:$det_differ"
  else
    say "runs: every executable prints the same bytes and exits alike on each input"
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
  det_packages=$(package_options "$1")
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
