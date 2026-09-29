# The profile fixtures: programs the compiler accepts, and programs it
# rejects with one explicit `unsupported (<reason>)` at the right line.

# header FILE FIELD: the value of `-- FIELD: <value>` among the lines of that
# form that start a profile fixture; the status is 1 without one.
header() {
  awk -v field="$2" '
    !/^--[ \t]*(expect|message|exit|stdout|packages):/ { exit }
    {
      key = $0; sub(/^--[ \t]*/, "", key); sub(/:.*$/, "", key)
      if (key == field) { value = $0; sub(/^--[ \t]*[a-z]+:[ \t]*/, "", value); found = 1 }
    }
    END { if (found) { print value; exit 0 } exit 1 }' "$1"
}

# reported_line FILE: the first line number of the first Idris location,
# `<file>:<line>:<col>--<line>:<col>`, in FILE.
reported_line() {
  grep -oE '(^|[[:space:]])[A-Za-z0-9_/.-]+:[0-9]+:[0-9]+--[0-9]+:[0-9]+([^A-Za-z0-9_]|$)' "$1" |
    head -n 1 | sed 's/^[[:space:]]*[A-Za-z0-9_/.-]*:\([0-9]*\):.*/\1/'
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

# profile_compile: $work/fixture/Main.idr to build/exec/Main, as an IO
# program with the packages its header names if its main is IO, and as a
# `main : Int` program otherwise.
profile_compile() {
  profile_main=$work/fixture/Main.idr
  if grep -Eq '^main[[:space:]]*:[[:space:]]*IO([^[:alnum:]_]|$)' "$profile_main"; then
    profile_packages=
    for profile_package in $(header "$profile_main" packages); do
      profile_packages="$profile_packages -p $profile_package"
    done
    compile_program --io $profile_packages "$profile_main" Main
  else
    compile_program --int "$profile_main" "$work/fixture/build/exec/Main"
  fi
}

# profile_reject FIXTURE: `tests/profile/vN/reject/<reason>-<desc>.idr`, or a
# directory of that name holding Main.idr and its other modules, whose first
# line is `-- expect: <reason>, line <n>` (and then, optionally,
# `-- message: <text>`), <reason> being the phrase the compiler gives and the
# name starting with it, words joined by dashes. It is rejected with exit
# status 1 and exactly one `unsupported (<reason>)`, reported on line n, and
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
  if grep -qF "unsupported ($reject_reason)" "$work/compile.all" && [ "$reject_count" -eq 1 ]; then
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

# profile_accept FIXTURE: `tests/profile/vN/accept/<desc>.idr`, or a
# directory of that name holding Main.idr: it compiles with every artifact
# written. With `-- exit: <status>` or `-- stdout: <text with \n escapes>` in
# its header it also runs, with those, and with nothing on stderr.
profile_accept() {
  if [ -d "$1" ]; then accept_main=$1/Main.idr; else accept_main=$1; fi
  profile_prepare "$1"
  profile_compile
  say "compile: exit $compiled"
  if [ "$compiled" -ne 0 ]; then
    show "$work/compile.out" "$work/compile.err"
    return
  fi
  artifacts "$work/fixture" Main.core Main.mlir Main.o Main
  accept_exit=$(header "$accept_main" exit)
  accept_has_exit=$?
  accept_stdout=$(header "$accept_main" stdout)
  accept_has_stdout=$?
  [ "$accept_has_exit" -eq 0 ] || [ "$accept_has_stdout" -eq 0 ] || return 0
  run_program accept "$work/fixture/build/exec/Main" /dev/null
  if [ "$accept_has_exit" -eq 0 ]; then
    accept_exit=$(printf '%s' "$accept_exit" | tr -d ' \t')
    if [ "$ran" -eq "$accept_exit" ]; then
      say "run: exit status as the header says"
    else
      say "run: exit $ran, the header says $accept_exit"
    fi
  else
    say "run: exit $ran"
  fi
  printf '%b' "$accept_stdout" > "$work/accept.expected"
  if cmp -s "$work/accept.expected" "$work/accept.out"; then
    say "stdout: as the header says"
  else
    say "stdout: differs from the header"
    diff "$work/accept.expected" "$work/accept.out" | head -n 20 | sed 's/^/  | /'
  fi
  empty stderr "$work/accept.err"
}
