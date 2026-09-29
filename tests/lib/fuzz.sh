# The fuzzer (tests/Fuzz.idr): generated closed expressions over every
# primitive, computed three ways.

# fuzz_run LABEL EXE: runs a program on empty stdin, Chez's (LABEL chez) or
# one of this compiler's; a failure is a problem of the current check.
fuzz_run() {
  if [ "$1" = chez ]; then run_program "$1" "$2" /dev/null; else run_ours "$1" "$2" /dev/null; fi
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

# fuzz SEED: the fuzzer (tests/Fuzz.idr). For each part, `runtime` and
# `static`, its program of SEED is compiled with evaluation, with
# --directive no-eval (the runtime part only: the static part's values
# cannot exist at runtime) and by the stock Chez backend; each runs on empty
# stdin, exits 0 and writes nothing on stderr. Then:
#   - each case prints one value on all its lines: the folders' (d), the one
#     idr-eval or the runtime computes (j) and the runtime's (r);
#   - --no-eval prints what evaluation prints, byte for byte;
#   - Chez prints the same, but for the lines of cases through libm (L),
#     which C libraries may round differently.
# IDRIS_MLIR_FUZZ_CASES sets the cases of a program (default 30), and
# IDRIS_MLIR_FUZZ_ROUNDS=N adds N seeds, SEED + 1000, SEED + 2000, ...; the
# output is the same for any of them.
fuzz() {
  fuzz_cases=${IDRIS_MLIR_FUZZ_CASES:-30}
  fuzz_rounds=${IDRIS_MLIR_FUZZ_ROUNDS:-0}
  for fuzz_part in runtime static; do
    : > "$work/fuzz.compiled"
    : > "$work/fuzz.agree"
    : > "$work/fuzz.noeval"
    : > "$work/fuzz.chez"
    fuzz_round=0
    while [ "$fuzz_round" -le "$fuzz_rounds" ]; do
      fuzz_seed=$(( $1 + 1000 * fuzz_round ))
      fuzz_round=$((fuzz_round + 1))
      fuzz_dir=$work/fuzz-$fuzz_part-$fuzz_seed
      mkdir -p "$fuzz_dir/eval" "$fuzz_dir/noeval" "$fuzz_dir/chez"
      if ! "$runtests" --fuzz-program "$fuzz_seed" "$fuzz_cases" "$fuzz_part" > "$fuzz_dir/Main.idr"; then
        printf '%s\n' "$fuzz_seed: no program" >> "$work/fuzz.compiled"
        continue
      fi
      fuzz_modes='eval chez'
      [ "$fuzz_part" = runtime ] && fuzz_modes='eval noeval chez'
      fuzz_ok=yes
      for fuzz_mode in $fuzz_modes; do
        cp "$fuzz_dir/Main.idr" "$fuzz_dir/$fuzz_mode/Main.idr"
        case $fuzz_mode in
          eval) compile_program --io "$fuzz_dir/eval/Main.idr" prog ;;
          noeval) compile_program --io --directive no-eval "$fuzz_dir/noeval/Main.idr" prog ;;
          chez)
            (cd "$fuzz_dir/chez" && bounded "$idris2" --no-banner --no-color --no-prelude \
               --cg chez -o prog Main.idr) > "$work/compile.out" 2> "$work/compile.err"
            compiled=$?
            ;;
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
      grep -v '^[djr]L' "$work/eval.out" > "$work/eval.host-independent"
      grep -v '^[djr]L' "$work/chez.out" > "$work/chez.host-independent"
      if ! cmp -s "$work/eval.host-independent" "$work/chez.host-independent"; then
        printf '%s\n' "$fuzz_seed: (< this compiler, > Chez)" >> "$work/fuzz.chez"
        diff "$work/eval.host-independent" "$work/chez.host-independent" | head -n 10 | sed 's/^/  | /' >> "$work/fuzz.chez"
      fi
    done
    fuzz_report "$fuzz_part: every build compiles, runs, exits 0 and writes nothing on stderr" fuzz.compiled
    fuzz_report "$fuzz_part: each case prints one value, whoever computes it" fuzz.agree
    [ "$fuzz_part" = runtime ] &&
      fuzz_report "$fuzz_part: --no-eval prints what evaluation prints" fuzz.noeval
    fuzz_report "$fuzz_part: Chez prints the same, the libm lines aside" fuzz.chez
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
