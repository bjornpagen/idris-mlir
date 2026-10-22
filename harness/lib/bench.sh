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
    # shellcheck disable=SC2046 # the packages are words
    compile_checked $(package_options "$root/bench/$bs_name") "$work/$bs_name/Main.idr" prog
    if [ "$compiled" -ne 0 ]; then
      say "$bs_name: compile exit $compiled"
      show "$work/compile.out" "$work/compile.err"
      continue
    fi
    run_program "$bs_name" "$work/$bs_name/build/exec/prog" "$1/$bs_name.in"
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
