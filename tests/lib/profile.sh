# The profile fixtures: programs the compiler accepts, and programs it
# rejects with one explicit `unsupported (<reason>)` at the right line.

# header FILE FIELD: the value of `-- FIELD: <value>` among the lines of that
# form that start a profile fixture; the status is 1 without one.
header() {
  awk -v field="$2" '
    !/^--[ \t]*(expect|message):/ { exit }
    {
      key = $0; sub(/^--[ \t]*/, "", key); sub(/:.*$/, "", key)
      if (key == field) { value = $0; sub(/^--[ \t]*[a-z]+:[ \t]*/, "", value); found = 1 }
    }
    END { if (found) { print value; exit 0 } exit 1 }' "$1"
}

# reported_line FILE: the line number of the first error's location in
# FILE, as either side prints one at the start of a line: Idris on a line of
# its own, `<module>:<line>:<col>--<line>:<col>`, after the message (which
# may itself name locations); MLIR before the message,
# `<file>:<line>:<col>: error: ...`.
reported_line() {
  grep -E '^[A-Za-z0-9_/.-]+:[0-9]+:[0-9]+(--[0-9]+:[0-9]+[[:space:]]*$|: error:)' "$1" |
    head -n 1 | sed 's/^[A-Za-z0-9_/.-]*:\([0-9]*\):.*/\1/'
}

# profile_prepare FIXTURE: the fixture in $work/fixture, a single file as
# Main.idr.
profile_prepare() {
  mkdir "$work/fixture"
  if [ -d "$1" ]; then
    copy_fixture "$1" "$work/fixture"
  else
    cp "$1" "$work/fixture/Main.idr"
  fi
}

# profile_compile: $work/fixture/Main.idr to build/exec/Main, with the
# installed packages its `packages` names; with `demand-in-place` it makes
# the in-place promise, which a program can break.
profile_compile() {
  profile_options=
  if [ -f "$work/fixture/packages" ]; then
    for profile_package in $(cat "$work/fixture/packages"); do
      profile_options="$profile_options -p $profile_package"
    done
  fi
  [ -f "$work/fixture/demand-in-place" ] && profile_options="$profile_options --demand-in-place"
  # shellcheck disable=SC2086 # the packages and the promise are words
  compile_program $profile_options "$work/fixture/Main.idr" Main
}

# profile_reject FIXTURE: `tests/reject/<reason>-<desc>/`, a directory holding
# Main.idr and its other modules, whose first
# line is `-- expect: <reason>, line <n>` (and then, optionally,
# `-- message: <text>`), <reason> being the phrase the compiler gives and the
# name starting with it, words joined by dashes. It is rejected with exit
# status 3 and exactly one `unsupported (<reason>)`, reported on line n, and
# leaves no artifact.
profile_reject() {
  if [ -d "$1" ]; then reject_main=$1/Main.idr; else reject_main=$1; fi
  reject_name=$(fixture_name "$1")
  reject_expect=$(header "$reject_main" expect)
  reject_reason=$(printf '%s\n' "$reject_expect" | sed -n 's/^\([a-z][a-z -]*[a-z]\), line \([0-9][0-9]*\)$/\1/p')
  reject_line=$(printf '%s\n' "$reject_expect" | sed -n 's/^\([a-z][a-z -]*[a-z]\), line \([0-9][0-9]*\)$/\2/p')
  if [ -z "$reject_reason" ]; then
    say "$reject_name: the first line must be '-- expect: <reason>, line <n>'"
    return
  fi
  reject_prefix=$(printf '%s' "$reject_reason" | tr ' ' '-')
  case $reject_name in
    "$reject_prefix"*) ;;
    *) say "$reject_name does not start with $reject_prefix"; return ;;
  esac
  profile_prepare "$1"
  profile_compile
  say "compile: exit $compiled"
  cat "$work/compile.out" "$work/compile.err" > "$work/compile.all"
  reject_count=$(grep -o 'unsupported (' "$work/compile.all" | wc -l | tr -d ' ')
  # A rejection is the user's error. An internal error, which may quote a
  # diagnostic of idris-mlir's that reads the same, is the compiler's.
  if grep -qF 'internal error' "$work/compile.all"; then
    say "unsupported ($reject_reason): an internal error, not a rejection"
    show "$work/compile.all"
  elif grep -qF "unsupported ($reject_reason)" "$work/compile.all" && [ "$reject_count" -eq 1 ]; then
    say "unsupported ($reject_reason): the only error"
  else
    say "unsupported ($reject_reason): expected once, among $reject_count unsupported errors"
    show "$work/compile.all"
  fi
  reject_reported=$(reported_line "$work/compile.all")
  if [ "$reject_reported" = "$reject_line" ]; then
    say "line: as the header says"
  else
    say "line: ${reject_reported:-none} reported, the header says $reject_line"
  fi
  if reject_message=$(header "$reject_main" message); then
    if grep -qF -- "$reject_message" "$work/compile.all"; then
      say "message: as the header says"
    else
      say "message: not in the output: $reject_message"
    fi
  fi
  no_artifacts "$work/fixture"
}

# profile_accept FIXTURE: `tests/accept/<desc>/`, a directory holding Main.idr
# and its other modules: it compiles with every artifact written. With an
# expected-stdout or an expected-exit beside it, it also runs, printing
# that stdout (none without the file) and exiting with that status (0
# without the file), with nothing on stderr.
profile_accept() {
  accept_fixture=$(cd "$1" && pwd)
  profile_prepare "$accept_fixture"
  profile_compile
  say "compile: exit $compiled"
  if [ "$compiled" -ne 0 ]; then
    show "$work/compile.out" "$work/compile.err"
    return
  fi
  artifacts "$work/fixture" Main.core Main.mlir Main.o Main
  [ -f "$accept_fixture/expected-stdout" ] || [ -f "$accept_fixture/expected-exit" ] || return 0
  run_ours accept "$work/fixture/build/exec/Main" /dev/null
  accept_exit=0
  [ -f "$accept_fixture/expected-exit" ] && accept_exit=$(first_word "$accept_fixture/expected-exit")
  if [ "$ran" -eq "$accept_exit" ]; then
    say "run: exit status as expected"
  else
    say "run: exit $ran, expected $accept_exit"
  fi
  : > "$work/accept.expected"
  [ -f "$accept_fixture/expected-stdout" ] && cp "$accept_fixture/expected-stdout" "$work/accept.expected"
  if cmp -s "$work/accept.expected" "$work/accept.out"; then
    say "stdout: as expected"
  else
    say "stdout: differs from expected-stdout"
    diff "$work/accept.expected" "$work/accept.out" | head -n 20 | sed 's/^/  | /'
  fi
  empty stderr "$work/accept.err"
}
