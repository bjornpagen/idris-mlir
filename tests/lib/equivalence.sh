# Compile-time evaluation changes no program's behaviour: every e2e program
# with and without it.

# equivalent FIXTURE: an e2e fixture compiled twice, with evaluation and
# with `--directive no-eval`, which leaves every closed call to runtime: both executables must print the
# same stdout and exit with the same status on the fixture's stdin. Crash
# messages are not compared. A fixture that --no-eval rejects with a user
# error (a value the profile forbids at runtime, which only evaluation
# removes) is listed with the reason, not failed; the listing is the test's
# expected output.
equivalent() {
  eq_fixture=${1%/}
  eq_name=${eq_fixture##*/}
  eq_dir=$work/eq/$eq_name
  mkdir -p "$eq_dir/eval" "$eq_dir/noeval"
  eq_stdin=/dev/null
  eq_packages=
  if [ -f "$eq_fixture/Main.idr" ]; then
    eq_flow=io
    [ -f "$eq_fixture/stdin" ] && eq_stdin=$eq_fixture/stdin
    if [ -f "$eq_fixture/packages" ]; then
      for eq_package in $(cat "$eq_fixture/packages"); do eq_packages="$eq_packages -p $eq_package"; done
    fi
  else
    eq_flow=int
  fi
  for eq_mode in eval noeval; do
    case $eq_name in
      prim-*)
        if ! "$runtests" --sem-program "$eq_name" > "$eq_dir/$eq_mode/Prog.idr" 2> "$work/sem.err"; then
          say "$eq_name: no semantics program"
          return
        fi
        ;;
      *) copy_fixture "$eq_fixture" "$eq_dir/$eq_mode" ;;
    esac
    eq_directives=
    [ "$eq_mode" = noeval ] && eq_directives='--directive no-eval'
    # shellcheck disable=SC2086 # the packages and directives are words
    if [ "$eq_flow" = io ]; then
      compile_program --io $eq_packages $eq_directives "$eq_dir/$eq_mode/Main.idr" prog
      eq_exe=$eq_dir/$eq_mode/build/exec/prog
    else
      compile_program --int $eq_directives "$eq_dir/$eq_mode/Prog.idr" "$eq_dir/$eq_mode/build/exec/Prog"
      eq_exe=$eq_dir/$eq_mode/build/exec/Prog
    fi
    if [ "$compiled" -ne 0 ]; then
      eq_reason=$(rejection_reason)
      if [ "$eq_mode" = noeval ] && [ "$compiled" -eq 1 ] && [ -n "$eq_reason" ]; then
        say "$eq_name: compiles only with evaluation: $eq_reason"
      else
        say "$eq_name: $eq_mode: compile exit $compiled"
        show "$work/compile.out" "$work/compile.err"
      fi
      return
    fi
    run_ours "$eq_mode" "$eq_exe" "$eq_stdin" small
    eval "eq_status_$eq_mode=\$ran"
  done
  if ! cmp -s "$work/eval.out" "$work/noeval.out"; then
    say "$eq_name: stdout differs (< evaluation, > --no-eval)"
    diff "$work/eval.out" "$work/noeval.out" | head -n 20 | sed 's/^/  | /'
  elif [ "$eq_status_eval" -ne "$eq_status_noeval" ]; then
    say "$eq_name: same stdout, but exit $eq_status_eval with evaluation and $eq_status_noeval with --no-eval"
  else
    say "$eq_name: same stdout and exit status"
  fi
}

# equivalence VERSION [sem]: `equivalent` on every fixture of
# tests/e2e/VERSION, in order; with `sem`, on its generated semantics
# fixtures (the integer primitives) alone, and without, on the others.
equivalence() {
  for eq_base in $(cd "$root/tests/e2e/$1" && ls | LC_ALL=C sort); do
    [ -d "$root/tests/e2e/$1/$eq_base" ] || continue
    case $eq_base in
      prim-*) [ "${2-}" = sem ] || continue ;;
      *) [ "${2-}" = sem ] && continue ;;
    esac
    equivalent "$root/tests/e2e/$1/$eq_base"
  done
}
