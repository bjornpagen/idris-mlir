# Running a compiled program.

# run_program NAME EXE INPUT [small]: runs EXE with stdin from INPUT, its
# stdout and stderr in $work/NAME.out and $work/NAME.err, its exit status in
# $ran. With `small`, on a 1 MiB stack: the process's, and the reserved
# one a program this compiler built runs on (IDRIS_RT_STACK).
run_program() {
  if [ "${4-}" = small ]; then
    ( ulimit -s 1024 && IDRIS_RT_STACK=1048576 && export IDRIS_RT_STACK && bounded "$2" ) \
      < "$3" > "$work/$1.out" 2> "$work/$1.err"
  else
    bounded "$2" < "$3" > "$work/$1.out" 2> "$work/$1.err"
  fi
  ran=$?
}

# run_ours NAME EXE INPUT [small]: run_program for a program this compiler
# built, which must free every heap cell it allocates. With IDRIS_RT_LIVE=1
# its runtime ends a normal exit, main's return with status 0, by writing
# `idris-rt: live cells N` on stderr, N being the cells still live. A crash
# writes no count, and nor does an exit with a status of the program's own
# (exitWith), which ends the process holding what it holds. A count of 0 is
# taken off stderr, which is then checked as before; any other count stays,
# and a missing one is said there, so that every check that stderr is empty
# sees the leak. After any other status stderr stays as the program wrote
# it: a crash's is only searched for its cause, and a count after an exit
# is a line a check that stderr is empty sees. The status is all that
# tells an exit from main's return, so exitWith ExitSuccess reads as a
# return whose count is missing.
run_ours() {
  IDRIS_RT_LIVE=1
  export IDRIS_RT_LIVE
  run_program "$@"
  unset IDRIS_RT_LIVE
  [ "$ran" -eq 0 ] || return 0
  case $(tail -n 1 "$work/$1.err") in
    'idris-rt: live cells 0')
      sed '$d' "$work/$1.err" > "$work/$1.err.counted"
      mv "$work/$1.err.counted" "$work/$1.err" ;;
    'idris-rt: live cells '*) ;;
    *) say "idris-rt: no count of live cells at exit" >> "$work/$1.err" ;;
  esac
}
