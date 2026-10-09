# The two levels (tests/TwoLevels.idr): closed terms, compiled and run,
# against the values their corpus's expected file records.

# two_levels CORPUS...: for each corpus, `primitives` or `prelude`, its
# terms are compiled by this compiler into a program that prints each as
# `t<n> <value>`, run on empty stdin. It must print the test's
# expected-<corpus>, line for line, but for the terms whose value depends on
# the target by design (`-- host-dependent:` in Terms.idr: the libm
# functions, whose last places are the platform libm's), which are listed
# and must each print a line, whatever its value.
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
    # The terms not compared, and why.
    sed -n 's/^-- host-dependent: \(t[0-9]*\) \(.*\)$/\1 \2/p' "$tl_dir/Terms.idr" > "$work/tl.host"
    while IFS= read -r tl_host; do
      tl_term=${tl_host%% *}
      tl_text=$(sed -n "s/^$tl_term = //p" "$tl_dir/Terms.idr")
      say "$tl_corpus: not compared, host-dependent: ${tl_host#* }: $tl_text"
    done < "$work/tl.host"
    # Line by line, t<n> <value>; a host-dependent term that prints nothing
    # shows as a line of its own.
    awk 'FILENAME == ARGV[1] { host[$1] = 1; next }
         ($1 in host) { printed[$1] = 1; next }
         { print }
         END { for (t in host) if (!(t in printed)) print t " printed nothing" }' \
      "$work/tl.host" "$work/terms.out" > "$work/terms.compared"
    if [ ! -f "$here/expected-$tl_corpus" ]; then
      say "$tl_corpus: no expected-$tl_corpus"
    elif cmp -s "$here/expected-$tl_corpus" "$work/terms.compared"; then
      say "$tl_corpus: prints expected-$tl_corpus, the host-dependent terms aside"
    else
      say "$tl_corpus: prints otherwise (< expected-$tl_corpus, > printed)"
      diff "$here/expected-$tl_corpus" "$work/terms.compared" | head -n 20 | sed 's/^/  | /'
    fi
  done
}
