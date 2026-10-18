# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The two levels (tests/TwoLevels.idr): closed terms, compiled and run,
# against the values their corpus's expected file records.

# two_levels CORPUS...: for each corpus, `primitives` or `prelude`, its
# terms are compiled by this compiler into a program that prints each as
# `t<n> <value>`, run on empty stdin. The runner reads what it printed
# against the test's expected-<corpus>, each line `<term> = <value>`
# (runtests --two-levels-check): it lists the terms whose value depends on
# the target by design (the libm functions, whose last places are the
# platform libm's), which must each print a line, whatever its value, and
# holds every other term to its recorded value.
two_levels() {
  for tl_corpus; do
    tl_dir=$work/tl-$tl_corpus
    mkdir -p "$tl_dir"
    if ! "$runtests" --two-levels-program "$tl_corpus" terms > "$tl_dir/Terms.idr" ||
       ! "$runtests" --two-levels-program "$tl_corpus" main > "$tl_dir/Main.idr"; then
      say "$tl_corpus: no program"
      continue
    fi
    compile_program "$tl_dir/Main.idr" prog
    say "$tl_corpus: compile: exit $compiled"
    if [ "$compiled" -ne 0 ]; then
      show "$work/compile.out" "$work/compile.err"
      continue
    fi
    run_ours terms "$tl_dir/build/exec/prog" /dev/null
    say "$tl_corpus: run: exit $ran"
    empty "$tl_corpus: stderr" "$work/terms.err"
    if ! "$runtests" --two-levels-check "$tl_corpus" "$work/terms.out" "$here/expected-$tl_corpus" \
         2> "$work/tl-check.err"; then
      say "$tl_corpus: no check"
      show "$work/tl-check.err"
    fi
  done
}
