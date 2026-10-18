# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The benchmarks of bench/ as a smoke test: each builds with this compiler
# and, on a small input, prints the output recorded for it. Nothing is
# timed; bench/run.sh times them, on inputs too large for a test.

# bench_smoke DIR: every benchmark, bench/<name>/Main.idr as bench/run.sh
# builds it, run on DIR/<name>.in, prints DIR/<name>.out, exits 0 and
# writes nothing on stderr.
bench_smoke() {
  for bs_name in $(cd "$root/bench" && ls | LC_ALL=C sort); do
    bs_main=$root/bench/$bs_name/Main.idr
    [ -f "$bs_main" ] || continue
    if [ ! -f "$1/$bs_name.in" ] || [ ! -f "$1/$bs_name.out" ]; then
      say "$bs_name: no recorded input and output in ${1##*/}"
      continue
    fi
    mkdir "$work/$bs_name"
    cp "$bs_main" "$work/$bs_name/"
    bs_packages=
    if [ -f "$root/bench/$bs_name/packages" ]; then
      for bs_package in $(cat "$root/bench/$bs_name/packages"); do bs_packages="$bs_packages -p $bs_package"; done
    fi
    # shellcheck disable=SC2086 # the packages are words
    compile_program $bs_packages "$work/$bs_name/Main.idr" prog
    if [ "$compiled" -ne 0 ]; then
      say "$bs_name: compile exit $compiled"
      show "$work/compile.out" "$work/compile.err"
      continue
    fi
    run_ours "$bs_name" "$work/$bs_name/build/exec/prog" "$1/$bs_name.in"
    if [ "$ran" -ne 0 ] || [ -s "$work/$bs_name.err" ]; then
      say "$bs_name: exit $ran"
      show "$work/$bs_name.err"
    elif cmp -s "$1/$bs_name.out" "$work/$bs_name.out"; then
      say "$bs_name: prints the recorded output"
    else
      say "$bs_name: prints another output (< recorded, > printed)"
      diff "$1/$bs_name.out" "$work/$bs_name.out" | head -n 20 | sed 's/^/  | /'
    fi
  done
}
