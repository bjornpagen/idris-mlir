# The fuzzer (tests/Fuzz.idr): generated closed expressions over every
# primitive, computed three ways, in two builds, and held to the values its
# seed's expected files record.

# The cases of a program: those of the programs whose output a seed's
# expected files (expected-runtime, expected-static) hold.
fuzz_cases=30

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
fuzz() {
  fuzz_seed=$1
  for fuzz_part in runtime static; do
    : > "$work/fuzz.compiled"
    : > "$work/fuzz.agree"
    : > "$work/fuzz.noeval"
    : > "$work/fuzz.expected"
    fuzz_check "$fuzz_part"
    fuzz_report "$fuzz_part: every build compiles, runs, exits 0 and writes nothing on stderr" fuzz.compiled
    fuzz_report "$fuzz_part: each case prints one value, whoever computes it" fuzz.agree
    [ "$fuzz_part" = runtime ] &&
      fuzz_report "$fuzz_part: --no-eval prints what evaluation prints" fuzz.noeval
    fuzz_report "$fuzz_part: prints expected-$fuzz_part, the libm lines aside" fuzz.expected
  done
}

# fuzz_check PART: the program of $fuzz_seed for PART, compiled, run and
# checked, its problems in the files fuzz reports.
fuzz_check() {
  fuzz_dir=$work/fuzz-$1-$fuzz_seed
  mkdir -p "$fuzz_dir/eval" "$fuzz_dir/noeval"
  if ! "$runtests" --fuzz-program "$fuzz_seed" "$fuzz_cases" "$1" > "$fuzz_dir/Main.idr"; then
    printf '%s\n' "$fuzz_seed: no program" >> "$work/fuzz.compiled"
    return
  fi
  fuzz_modes=eval
  [ "$1" = runtime ] && fuzz_modes='eval noeval'
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
  [ "$fuzz_ok" = yes ] || return
  fuzz_agree "$work/eval.out" "with evaluation"
  if [ "$1" = runtime ]; then
    fuzz_agree "$work/noeval.out" "with --no-eval"
    if ! cmp -s "$work/eval.out" "$work/noeval.out"; then
      printf '%s\n' "$fuzz_seed: (< evaluation, > --no-eval)" >> "$work/fuzz.noeval"
      diff "$work/eval.out" "$work/noeval.out" | head -n 10 | sed 's/^/  | /' >> "$work/fuzz.noeval"
    fi
  fi
  fuzz_expected=$here/expected-$1
  if [ ! -f "$fuzz_expected" ]; then
    printf '%s\n' "$fuzz_seed: no expected-$1" >> "$work/fuzz.expected"
    return
  fi
  grep -v '^[djr]L' "$work/eval.out" > "$work/fuzz.printed"
  if ! cmp -s "$fuzz_expected" "$work/fuzz.printed"; then
    printf '%s\n' "$fuzz_seed: (< expected-$1, > evaluation)" >> "$work/fuzz.expected"
    diff "$fuzz_expected" "$work/fuzz.printed" | head -n 10 | sed 's/^/  | /' >> "$work/fuzz.expected"
  fi
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
