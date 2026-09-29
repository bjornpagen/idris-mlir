# Running a compiled program.

# run_program NAME EXE INPUT [small]: runs EXE with stdin from INPUT, its
# stdout and stderr in $work/NAME.out and $work/NAME.err, its exit status in
# $ran. With `small`, on a 1 MiB stack.
run_program() {
  if [ "${4-}" = small ]; then
    ( ulimit -s 1024 && bounded "$2" ) < "$3" > "$work/$1.out" 2> "$work/$1.err"
  else
    bounded "$2" < "$3" > "$work/$1.out" 2> "$work/$1.err"
  fi
  ran=$?
}

# run_ours NAME EXE INPUT [small]: run_program for a program this compiler
# built, which must free every heap cell it allocates. With IDRIS_RT_LIVE=1
# its runtime ends a normal exit by writing `idris-rt: live cells N` on
# stderr, N being the cells still live; a crash writes no count. A count of
# 0 is taken off stderr, which is then checked as before; any other count
# stays, and a missing one is said there, so that every check that stderr
# is empty sees the leak. A crash's stderr is only searched for its cause,
# which the added line does not hide.
run_ours() {
  IDRIS_RT_LIVE=1
  export IDRIS_RT_LIVE
  run_program "$@"
  unset IDRIS_RT_LIVE
  case $(tail -n 1 "$work/$1.err") in
    'idris-rt: live cells 0')
      sed '$d' "$work/$1.err" > "$work/$1.err.counted"
      mv "$work/$1.err.counted" "$work/$1.err" ;;
    'idris-rt: live cells '*) ;;
    *) say "idris-rt: no count of live cells at exit" >> "$work/$1.err" ;;
  esac
}
