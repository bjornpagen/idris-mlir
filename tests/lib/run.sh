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
