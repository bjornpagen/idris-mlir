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
# built. With IDRIS_RT_LIVE=1 its runtime ends a normal exit by writing
# `idris-rt: live cells N` on stderr, N being the heap cells it allocated
# and did not free; a crash writes no count. The count is kept in
# $live_cells (empty without one) and a count of 0 is taken off stderr, so
# that stderr is checked as it was; any other count stays there as well,
# where every check of stderr sees it.
run_ours() {
  IDRIS_RT_LIVE=1
  export IDRIS_RT_LIVE
  run_program "$@"
  unset IDRIS_RT_LIVE
  live_cells=$(tail -n 1 "$work/$1.err" | sed -n 's/^idris-rt: live cells \([0-9][0-9]*\)$/\1/p')
  if [ "$live_cells" = 0 ]; then
    sed '$d' "$work/$1.err" > "$work/$1.err.counted"
    mv "$work/$1.err.counted" "$work/$1.err"
  fi
}
