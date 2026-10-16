# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The fuzzer (tests/Fuzz.idr): generated closed expressions over every
# primitive, each written four ways in one build, held to each other, to
# the folders, and over the integers to what the primitives mean. Every
# check is a relation the program's own output and modules must satisfy,
# so none depends on what a seed draws or in what order.

# The cases of a program: the size the seeds' recorded outputs had, kept.
# That thirty compile within the test's limits at every thread count a seed
# draws is for the owner's build to confirm.
fuzz_cases=30

# fuzz SEED: for each part, `runtime` then `static`, the program of SEED,
# compiled at the seed's thread count with every module dumped and run on
# its stdin, and four checks, a line each:
#   - the build compiles, runs, exits 0 and writes nothing on stderr, and
#     no case ran out of its tape;
#   - each case's lines (d, j, r, s, with or without L) print one value;
#   - after idr-optimize no op of main computes on constants alone
#     (folded=@Main.main), so the folders computed every d line;
#   - each case the model covers prints the value its m line states.
# The first case that disagrees or misses its model is shrunk (fuzz_shrink)
# under its check's line.
fuzz() {
  fuzz_seed=$1
  if ! fuzz_threads=$("$runtests" --fuzz-program threads "$fuzz_seed"); then
    say "fuzz: no thread count for seed $fuzz_seed"
    return
  fi
  for fuzz_part in runtime static; do
    for fuzz_check_file in compiled agree folded model; do
      : > "$work/fuzz.$fuzz_check_file"
    done
    fuzz_failing=
    fuzz_check "$fuzz_part"
    fuzz_report "$fuzz_part: every build compiles, runs, exits 0 and writes nothing on stderr" compiled
    fuzz_report "$fuzz_part: each case prints one value, whoever computes it" agree
    case $fuzz_failing in *' agree') fuzz_shrink "$fuzz_part" $fuzz_failing ;; esac
    fuzz_report "$fuzz_part: every d line is folded" folded
    fuzz_report "$fuzz_part: each case over integers prints its documented value" model
    case $fuzz_failing in *' model') fuzz_shrink "$fuzz_part" $fuzz_failing ;; esac
  done
}

# fuzz_check PART: the program of $fuzz_seed for PART, its stdin and its
# model generated, compiled, run and checked, its problems in the files fuzz
# reports, and in $fuzz_failing the first failing case and how it fails.
fuzz_check() {
  fuzz_dir=$work/fuzz-$1-$fuzz_seed
  mkdir -p "$fuzz_dir/prog"
  for fuzz_file in main stdin model; do
    if ! "$runtests" --fuzz-program program "$fuzz_seed" "$fuzz_cases" "$1" "$fuzz_file" > "$fuzz_dir/$fuzz_file"; then
      say "$fuzz_seed: no $fuzz_file" >> "$work/fuzz.compiled"
      return
    fi
  done
  # A case whose tape ran out is a valid case, but not the one its seed
  # drew: the derivation of the tape's length fell short.
  case $(head -n 1 "$fuzz_dir/main") in
    '-- overran'*) say "$fuzz_seed: $(head -n 1 "$fuzz_dir/main" | sed 's/^-- //')" >> "$work/fuzz.compiled" ;;
  esac
  cp "$fuzz_dir/main" "$fuzz_dir/prog/Main.idr"
  fuzz_dumps=$fuzz_dir/prog/build/exec/prog.dump
  # shellcheck disable=SC2046 # the dump options are words
  compile_program "--num-threads=$fuzz_threads" $(dump_options "$fuzz_dumps") "$fuzz_dir/prog/Main.idr" prog
  if [ "$compiled" -ne 0 ]; then
    say "$fuzz_seed: compile exit $compiled" >> "$work/fuzz.compiled"
    cat "$work/compile.out" "$work/compile.err" | head -n 10 | sed 's/^/  | /' >> "$work/fuzz.compiled"
    return
  fi
  run_ours prog "$fuzz_dir/prog/build/exec/prog" "$fuzz_dir/stdin"
  if [ "$ran" -ne 0 ] || [ -s "$work/prog.err" ]; then
    say "$fuzz_seed: prog exited $ran" >> "$work/fuzz.compiled"
    head -n 5 "$work/prog.err" | sed 's/^/  | /' >> "$work/fuzz.compiled"
    return
  fi
  if ! fuzz_optimized=$(step_module idr-optimize "$(artifact_file "$fuzz_dir/prog" prog module)" "$fuzz_dumps"); then
    say "$fuzz_seed: no module dumped after idr-optimize" >> "$work/fuzz.folded"
  elif ! expect_holds "$fuzz_optimized" folded=@Main.main; then
    say "$fuzz_seed: main computes on constants after idr-optimize" >> "$work/fuzz.folded"
    show "$work/expect.log" >> "$work/fuzz.folded"
  fi
  fuzz_failing=$(fuzz_compare "$work/prog.out" "$fuzz_dir/model" "$fuzz_cases" "$work/fuzz.agree" "$work/fuzz.model")
}

# fuzz_compare OUTPUT MODEL CASES AGREE MISSED: the problems of a program's
# OUTPUT, of CASES cases, against its MODEL (lines `m<n> <value>`): in
# AGREE, a case whose lines print two values; in MISSED, a case the model
# covers that prints another value, or nothing. Prints the first failing
# case, `<n> agree` or `<n> model` (a disagreement first), or nothing. A
# value may hold NUL (a cast to Char of a value that is no scalar gives
# 0), at which awk would end it: NUL is read as the byte \377, which no
# UTF-8 text holds.
fuzz_compare() {
  LC_ALL=C tr '\000' '\377' < "$1" |
    LC_ALL=C awk -v seed="$fuzz_seed" -v cases="$3" -v agree="$4" -v missed="$5" '
      FILENAME == ARGV[1] { model[substr($1, 2)] = $2; next }
      $1 ~ /^[djrs]L?[0-9]+$/ {
        label = $1; n = label; sub(/^[djrs]L?/, "", n)
        value = $0; sub(/^[^ ]* /, "", value)
        if (!(n in first)) { first[n] = value; firstLabel[n] = label }
        else if (value != first[n] && !(n in disagrees)) {
          disagrees[n] = 1
          printf "%s: case %s: %s %s, but %s %s\n", seed, n, firstLabel[n], first[n], label, value >> agree
        }
        if ((n in model) && value != model[n] && !(n in misses)) {
          misses[n] = 1
          printf "%s: case %s: m%s %s, but %s %s\n", seed, n, n, model[n], label, value >> missed
        }
      }
      END {
        for (i = 1; i <= cases; i++) {
          n = i ""
          if ((n in model) && !(n in first)) {
            misses[n] = 1
            printf "%s: case %s: m%s %s, but no line\n", seed, n, n, model[n] >> missed
          }
        }
        for (i = 1; i <= cases; i++) {
          n = i ""
          if (n in disagrees) { print n " agree"; exit }
          if (n in misses) { print n " model"; exit }
        }
      }' "$2" -
}

# fuzz_shrink PART CASE HOW: case CASE of the seed's PART program fails
# (HOW: `agree`, its lines disagree; `model`, it misses its model), and its
# tape (runtests --fuzz-program tape) is shrunk: each candidate of the
# current tape (--fuzz-program shrink) is built as a one-case program and
# run, and the first whose case fails the same way becomes the current
# tape, a line saying so, and the candidates start again. Every candidate
# is before its tape in shortlex order, so the loop ends; no count of
# attempts stops it. Then the smallest failing case's function and lines.
fuzz_shrink() {
  if ! fuzz_tape=$("$runtests" --fuzz-program tape "$fuzz_seed" "$2" "$1"); then
    say "  | no tape for case $2"
    return
  fi
  if ! fuzz_fails_as "$1" "$fuzz_tape" "$3"; then
    say "  | case $2 does not fail alone, on its tape $fuzz_tape"
    return
  fi
  cp "$work/fuzz-try/Main.idr" "$work/fuzz.smallest.idr"
  cp "$work/try.out" "$work/fuzz.smallest.out"
  fuzz_shrinking=yes
  while [ -n "$fuzz_shrinking" ]; do
    fuzz_shrinking=
    "$runtests" --fuzz-program shrink "$fuzz_tape" > "$work/fuzz.candidates" || break
    while IFS= read -r fuzz_candidate; do
      if fuzz_fails_as "$1" "$fuzz_candidate" "$3" < /dev/null; then
        say "  | smaller failing tape: $fuzz_candidate"
        fuzz_tape=$fuzz_candidate
        cp "$work/fuzz-try/Main.idr" "$work/fuzz.smallest.idr"
        cp "$work/try.out" "$work/fuzz.smallest.out"
        fuzz_shrinking=yes
        break
      fi
    done < "$work/fuzz.candidates"
  done
  sed -n '/^c1 :/,/^$/p' "$work/fuzz.smallest.idr" | sed '/^$/d; s/^/  | /'
  LC_ALL=C tr '\000' '\377' < "$work/fuzz.smallest.out" | LC_ALL=C grep -E '^[djrs]L?1 ' | sed 's/^/  | /'
}

# fuzz_fails_as PART TAPE HOW: the one-case program of TAPE (--fuzz-program
# replay) compiles, runs to an exit of 0, and its case fails as HOW says;
# its source is $work/fuzz-try/Main.idr and its output $work/try.out.
fuzz_fails_as() {
  rm -rf "$work/fuzz-try"
  mkdir -p "$work/fuzz-try"
  for fuzz_file in main stdin model; do
    "$runtests" --fuzz-program replay "$2" "$1" "$fuzz_file" > "$work/fuzz-try/$fuzz_file" || return 1
  done
  cp "$work/fuzz-try/main" "$work/fuzz-try/Main.idr"
  compile_program "--num-threads=$fuzz_threads" "$work/fuzz-try/Main.idr" prog < /dev/null
  [ "$compiled" -eq 0 ] || return 1
  run_ours try "$work/fuzz-try/build/exec/prog" "$work/fuzz-try/stdin"
  [ "$ran" -eq 0 ] || return 1
  [ "$(fuzz_compare "$work/try.out" "$work/fuzz-try/model" 1 /dev/null /dev/null)" = "1 $3" ]
}

# fuzz_report TEXT CHECK: TEXT, then `ok`, or `failed` and the problems
# CHECK found.
fuzz_report() {
  if [ -s "$work/fuzz.$2" ]; then
    say "$1: failed"
    head -n 40 "$work/fuzz.$2"
  else
    say "$1: ok"
  fi
}
