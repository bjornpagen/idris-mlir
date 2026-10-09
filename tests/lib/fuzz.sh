# The fuzzer (tests/Fuzz.idr): generated closed expressions over every
# primitive, computed three ways, in two builds, and held to the values its
# seed's expected files record.

# The cases of a program by default: those of the programs whose output a
# seed's expected files (expected-runtime, expected-static) hold.
fuzz_recorded_cases=30

# fuzz_run LABEL EXE: runs one of this compiler's programs on empty stdin; a
# failure is a problem of the current check.
fuzz_run() {
  run_ours "$1" "$2" /dev/null
  if [ "$ran" -ne 0 ] || [ -s "$work/$1.err" ]; then
    printf '%s\n' "$fuzz_seed: $1 exited $ran" >> "$work/fuzz.compiled"
    head -n 5 "$work/$1.err" | sed 's/^/  | /' >> "$work/fuzz.compiled"
    return 1
  fi
}

# fuzz_agree OUTPUT: every case's lines (d<n>, j<n>, r<n>, with or without
# L) print one value; the disagreements are problems.
fuzz_agree() {
  awk -v seed="$fuzz_seed" -v what="$2" '
    $1 ~ /^[djr]L?[0-9]+$/ {
      key = substr($1, 2); value = $0; sub(/^[^ ]* /, "", value)
      if ((key in seen) && seen[key] != value)
        printf "%s: %s: case %s: %s, but %s\n", seed, what, key, seen[key], value
      else seen[key] = value
    }' "$1" >> "$work/fuzz.agree"
}

# fuzz_cases_through N FILE: FILE's lines of cases 1 to N, but the libm
# lines (L): what a program of another number of cases shares with the
# recorded one. Case k is drawn from the seed after cases 1 to k - 1, so it
# is the same in a program of any number of cases; the barriers (b) are
# drawn after the last case, so they are not.
fuzz_cases_through() {
  awk -v n="$1" '$1 ~ /^[djr][0-9]+$/ && substr($1, 2) + 0 <= n' "$2"
}

# fuzz SEED: the fuzzer (tests/Fuzz.idr). For each part, `runtime` and
# `static`, its program of SEED is compiled with evaluation and with
# --directive no-eval (the runtime part only: the static part's values
# cannot exist at runtime); each runs on empty stdin, exits 0 and writes
# nothing on stderr. Then:
#   - each case prints one value on all its lines: the folders' (d), the one
#     idr-eval or the runtime computes (j) and the runtime's (r);
#   - --no-eval prints what evaluation prints, byte for byte;
#   - evaluation prints the part's expected file in the test's directory,
#     expected-runtime or expected-static, but for the lines of cases
#     through libm (L): libm is not correctly rounded and the runtime calls
#     the platform's, so the last places of those values are the target's,
#     and the expected files are every target's.
# IDRIS_MLIR_FUZZ_CASES sets the cases of a program (by default the
# recorded programs', fuzz_recorded_cases), and IDRIS_MLIR_FUZZ_ROUNDS=N
# adds N seeds, SEED + 1000, SEED + 2000, ...; the output is the same for
# any of them. A program of another number of cases is held to the expected
# files on the cases it shares with theirs; the added seeds have none, and
# are held to the other checks only.
fuzz() {
  fuzz_cases=${IDRIS_MLIR_FUZZ_CASES:-$fuzz_recorded_cases}
  fuzz_rounds=${IDRIS_MLIR_FUZZ_ROUNDS:-0}
  for fuzz_part in runtime static; do
    : > "$work/fuzz.compiled"
    : > "$work/fuzz.agree"
    : > "$work/fuzz.noeval"
    : > "$work/fuzz.expected"
    fuzz_round=0
    while [ "$fuzz_round" -le "$fuzz_rounds" ]; do
      fuzz_seed=$(( $1 + 1000 * fuzz_round ))
      fuzz_round=$((fuzz_round + 1))
      fuzz_dir=$work/fuzz-$fuzz_part-$fuzz_seed
      mkdir -p "$fuzz_dir/eval" "$fuzz_dir/noeval"
      if ! "$runtests" --fuzz-program "$fuzz_seed" "$fuzz_cases" "$fuzz_part" > "$fuzz_dir/Main.idr"; then
        printf '%s\n' "$fuzz_seed: no program" >> "$work/fuzz.compiled"
        continue
      fi
      fuzz_modes=eval
      [ "$fuzz_part" = runtime ] && fuzz_modes='eval noeval'
      fuzz_ok=yes
      for fuzz_mode in $fuzz_modes; do
        cp "$fuzz_dir/Main.idr" "$fuzz_dir/$fuzz_mode/Main.idr"
        case $fuzz_mode in
          eval) compile_program "$fuzz_dir/eval/Main.idr" prog ;;
          noeval) compile_program --directive no-eval "$fuzz_dir/noeval/Main.idr" prog ;;
        esac
        if [ "$compiled" -ne 0 ]; then
          printf '%s\n' "$fuzz_seed: $fuzz_mode: compile exit $compiled" >> "$work/fuzz.compiled"
          cat "$work/compile.out" "$work/compile.err" | head -n 10 | sed 's/^/  | /' >> "$work/fuzz.compiled"
          fuzz_ok=no
          continue
        fi
        fuzz_run "$fuzz_mode" "$fuzz_dir/$fuzz_mode/build/exec/prog" || fuzz_ok=no
      done
      [ "$fuzz_ok" = yes ] || continue
      fuzz_agree "$work/eval.out" "with evaluation"
      if [ "$fuzz_part" = runtime ]; then
        fuzz_agree "$work/noeval.out" "with --no-eval"
        if ! cmp -s "$work/eval.out" "$work/noeval.out"; then
          printf '%s\n' "$fuzz_seed: (< evaluation, > --no-eval)" >> "$work/fuzz.noeval"
          diff "$work/eval.out" "$work/noeval.out" | head -n 10 | sed 's/^/  | /' >> "$work/fuzz.noeval"
        fi
      fi
      [ "$fuzz_seed" -eq "$1" ] || continue
      fuzz_expected=$here/expected-$fuzz_part
      if [ ! -f "$fuzz_expected" ]; then
        printf '%s\n' "$fuzz_seed: no expected-$fuzz_part" >> "$work/fuzz.expected"
        continue
      fi
      if [ "$fuzz_cases" -eq "$fuzz_recorded_cases" ]; then
        cp "$fuzz_expected" "$work/fuzz.recorded"
        grep -v '^[djr]L' "$work/eval.out" > "$work/fuzz.printed"
      else
        fuzz_shared=$fuzz_cases
        [ "$fuzz_shared" -le "$fuzz_recorded_cases" ] || fuzz_shared=$fuzz_recorded_cases
        fuzz_cases_through "$fuzz_shared" "$fuzz_expected" > "$work/fuzz.recorded"
        fuzz_cases_through "$fuzz_shared" "$work/eval.out" > "$work/fuzz.printed"
      fi
      if ! cmp -s "$work/fuzz.recorded" "$work/fuzz.printed"; then
        printf '%s\n' "$fuzz_seed: (< expected-$fuzz_part, > evaluation)" >> "$work/fuzz.expected"
        diff "$work/fuzz.recorded" "$work/fuzz.printed" | head -n 10 | sed 's/^/  | /' >> "$work/fuzz.expected"
      fi
    done
    fuzz_report "$fuzz_part: every build compiles, runs, exits 0 and writes nothing on stderr" fuzz.compiled
    fuzz_report "$fuzz_part: each case prints one value, whoever computes it" fuzz.agree
    [ "$fuzz_part" = runtime ] &&
      fuzz_report "$fuzz_part: --no-eval prints what evaluation prints" fuzz.noeval
    fuzz_report "$fuzz_part: prints expected-$fuzz_part, the libm lines aside" fuzz.expected
  done
}

# fuzz_report TEXT FILE: TEXT, then `ok`, or `failed` and FILE's problems.
fuzz_report() {
  if [ -s "$work/$2" ]; then
    say "$1: failed"
    head -n 40 "$work/$2"
  else
    say "$1: ok"
  fi
}
