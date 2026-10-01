# The two-level test (tests/TwoLevels.idr): Idris's own evaluator against
# the compiled program.

# two_levels CORPUS...: the two-level test (tests/TwoLevels.idr). The helper
# tests/twolevels, Idris's own evaluator as a backend of the stock driver, is
# built; for each corpus, `primitives` or `prelude`, its terms are
# normalised by it (the upper level), and compiled by this compiler (the
# lower level) and by Chez, each run on empty stdin. The lower level prints
# Idris's value for every term but those Idris does not reduce, those whose
# value depends on the host by design (`-- host-dependent:` in Terms.idr),
# and those the pinned Idris evaluates differently from its own backends
# (`-- idris-differs:`), all of which are listed; and Chez prints what the
# lower level prints, the host-dependent terms aside.
two_levels() {
  # The helper is an Idris backend built against the compiler's own modules,
  # which takes about a minute: one step, but a larger one.
  (step_limit=$(( 300 * time_scale ))
   cd "$root/tests/twolevels" && bounded "$idris2" --no-banner --no-color \
     --build-dir "$work/twolevels-build" --build twolevels.ipkg) > "$work/twolevels.log" 2>&1
  tl_built=$?
  tl_helper=$work/twolevels-build/exec/twolevels
  if [ "$tl_built" -ne 0 ] || [ ! -x "$tl_helper" ]; then
    say "helper: build exit $tl_built"
    show "$work/twolevels.log"
    return
  fi
  say "helper: built"
  for tl_corpus; do
    tl_dir=$work/tl-$tl_corpus
    mkdir -p "$tl_dir/upper" "$tl_dir/lower" "$tl_dir/chez"
    for tl_side in upper lower chez; do
      "$runtests" --two-levels-program "$tl_corpus" terms > "$tl_dir/$tl_side/Terms.idr" &&
        "$runtests" --two-levels-program "$tl_corpus" main > "$tl_dir/$tl_side/Main.idr" || {
          say "$tl_corpus: no program"
          continue 2
        }
    done
    (cd "$tl_dir/upper" && bounded "$tl_helper" --no-banner --no-color --no-prelude --cg twolevels \
       -o unused Main.idr) > "$work/upper.out" 2> "$work/upper.err"
    say "$tl_corpus: Idris's evaluator: exit $?"
    [ -s "$work/upper.err" ] && show "$work/upper.err"
    compile_program "$tl_dir/lower/Main.idr" prog
    say "$tl_corpus: compile: exit $compiled"
    if [ "$compiled" -ne 0 ]; then
      show "$work/compile.out" "$work/compile.err"
      continue
    fi
    run_ours lower "$tl_dir/lower/build/exec/prog" /dev/null
    say "$tl_corpus: run: exit $ran"
    empty "$tl_corpus: stderr" "$work/lower.err"
    (cd "$tl_dir/chez" && bounded "$idris2" --no-banner --no-color --no-prelude --cg chez \
       -o prog Main.idr) > "$work/chez.log" 2>&1
    say "$tl_corpus: chez: compile exit $?"
    run_program chez "$tl_dir/chez/build/exec/prog" /dev/null
    # The terms not compared with Idris's value, and why.
    sed -n 's/^-- host-dependent: \(t[0-9]*\) \(.*\)$/\1 host-dependent: \2/p' "$tl_dir/lower/Terms.idr" > "$work/tl.host"
    sed -n 's/^-- idris-differs: \(t[0-9]*\) \(.*\)$/\1 Idris evaluates it differently: \2/p' "$tl_dir/lower/Terms.idr" > "$work/tl.differs"
    awk '$2 == "stuck" { print $1 " not reduced by Idris" }' "$work/upper.out" > "$work/tl.stuck"
    cat "$work/tl.host" "$work/tl.differs" "$work/tl.stuck" | sort -t t -k 2 -n > "$work/tl.skipped"
    while IFS= read -r tl_skip; do
      tl_term=${tl_skip%% *}
      tl_text=$(sed -n "s/^$tl_term = //p" "$tl_dir/lower/Terms.idr")
      say "$tl_corpus: not compared with Idris: ${tl_skip#* }: $tl_text"
    done < "$work/tl.skipped"
    # Line by line: t<n> <value>.
    awk 'FILENAME == ARGV[1] { skip[$1] = 1; next }
         FILENAME == ARGV[2] { upper[$1] = $0; next }
         !($1 in skip) && upper[$1] != $0 { printf "  | %s: Idris: %s; this compiler: %s\n", $1, upper[$1], $0 }
        ' "$work/tl.skipped" "$work/upper.out" "$work/lower.out" > "$work/tl.diff"
    tl_upper_terms=$(wc -l < "$work/upper.out" | tr -d ' ')
    tl_lower_terms=$(wc -l < "$work/lower.out" | tr -d ' ')
    if [ -s "$work/tl.diff" ] || [ "$tl_upper_terms" -ne "$tl_lower_terms" ]; then
      say "$tl_corpus: this compiler prints Idris's value for every other term: failed ($tl_upper_terms against $tl_lower_terms lines)"
      head -n 40 "$work/tl.diff"
    else
      say "$tl_corpus: this compiler prints Idris's value for every other term"
    fi
    for tl_side in lower chez; do
      awk 'FILENAME == ARGV[1] { host[$1] = 1; next } !($1 in host)' \
        "$work/tl.host" "$work/$tl_side.out" > "$work/$tl_side.host-independent"
    done
    if cmp -s "$work/lower.host-independent" "$work/chez.host-independent"; then
      say "$tl_corpus: Chez prints the same, the host-dependent terms aside"
    else
      say "$tl_corpus: Chez prints differently (< this compiler, > Chez)"
      diff "$work/lower.host-independent" "$work/chez.host-independent" | head -n 20 | sed 's/^/  | /'
    fi
  done
}
