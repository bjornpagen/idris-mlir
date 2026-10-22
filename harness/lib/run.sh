# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Running a compiled program.

# run_program NAME EXE INPUT: runs EXE with stdin from INPUT, its stdout
# and stderr in $work/NAME.out and $work/NAME.err, its exit status, as sh
# reports it (128 plus a signal's number for a process a signal ended), in
# $ran. A program this compiler built for a test links the checked runtime
# (compile_checked), which ends a run that returns from main with a cell
# still live as the runtime's internal error: a leak is an ending like any
# other, never a line a test parses.
run_program() {
  bounded "$2" < "$3" > "$work/$1.out" 2> "$work/$1.err"
  ran=$?
}
