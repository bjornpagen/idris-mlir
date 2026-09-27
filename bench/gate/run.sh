#!/bin/sh
# Runs the memory gate (docs/plan.md 4.4; bench/gate/README.md):
#
#   bench/gate/run.sh [suite] [lowered] [threads] [linear]    (default: all)
#
#   suite    experiment 1: the eight programs in Idris (Chez), SML (MLton),
#            C, Koka and Lean; the Chez run is the baseline
#   lowered  experiment 2: hand-lowered rbtree, deriv and binarytrees on the
#            runtime prototype, against MLton, Lean and Koka
#   threads  experiment 3: ptrees, shmap and pipe on the prototype with
#            move-or-mark, against Go, with the prototype's atomic counts
#   linear   experiment 4: the linear red-black tree, static against
#            dynamic reuse, and the silent cliff in Koka and Lean
#
# Every program is timed RUNS times (default 5; CHEZ_RUNS for the Chez
# baseline, whose runs are the longest); the best time and the largest peak
# RSS are kept. Every output must equal the reference output
# (Chez's, or C's or Go's where there is no Idris version). Results go to
# $GATE_OUT/results (default build/gate/results): one Markdown table per
# experiment, the raw numbers in results.tsv, and verdicts in verdicts.txt.
#
# Exit status: 0 when every criterion that was checked passed and nothing
# was missing; 1 when a criterion failed, an output differed or a program
# failed; 2 when nothing failed but something could not be measured (a
# missing toolchain), so the gate is incomplete.
set -eu
GATE=$(cd "$(dirname "$0")" && pwd)
. "$GATE/lib.sh"

RES=$OUT/results
mkdir -p "$RES"
TSV=$RES/results.tsv
VERDICTS=$RES/verdicts.txt
FAILED=0
MISSING=0

# The factor by which a broken call site must slow Koka and Lean down to
# count as a cliff (experiment 4).
CLIFF=${CLIFF:-1.2}

# ---- helpers -----------------------------------------------------------------

le() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 <= b + 0) }'; }
lt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 < b + 0) }'; }
ratio() { awk -v a="$1" -v b="$2" 'BEGIN { if (b + 0 == 0) print "n/a"; else printf "%.2f", a / b }'; }
mib() { awk -v k="$1" 'BEGIN { printf "%.1f", k / 1024 }'; }
cell() { printf '%.3f s, %s MiB' "$1" "$(mib "$2")"; }

verdict() { # EXPERIMENT CRITERION RESULT(pass|FAIL|n/a) DETAIL
  printf '%-8s %-5s %s: %s\n' "$1" "$3" "$2" "$4" | tee -a "$VERDICTS" >&2
  case $3 in
    FAIL) FAILED=1 ;;
    n/a) MISSING=1 ;;
  esac
}

# measure EXP NAME LANG EXE INPUT: times EXE on INPUT; sets T (best
# seconds), K (peak KiB) and O (the output file); records a line in the TSV.
# Returns 1 (with the reason in WHY) when the program fails.
measure() {
  exp=$1; name=$2; lang=$3; exe=$4; input=$5
  tag=$exp-$name-$lang
  T=""; K=""; O=""; WHY=""
  runs=$RUNS
  [ "$lang" = chez ] && runs=${CHEZ_RUNS:-$RUNS}
  line=$(RUNS=$runs; measure_best "$exe" "$input" "$tag") ||
    { WHY="the run failed (see $OUT/out/$tag.err)"; return 1; }
  set -- $line
  T=$1; K=$2; O=$OUT/out/$tag.out
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$exp" "$name" "$lang" "$input" "$T" "$K" >> "$TSV"
}

# build and lowered run in a command substitution, so they leave the reason
# for a failure in this file, which failure reads.
WHYFILE=$OUT/.why
# failure EXP WHAT: the verdict when WHAT could not be measured: n/a for a
# missing toolchain, FAIL for a failed build or run.
failure() {
  r=$(cat "$WHYFILE" 2>/dev/null || true)
  case $r in
    no\ *) verdict "$1" "$2" n/a "$r" ;;
    "") verdict "$1" "$2" FAIL "${WHY:-failed}" ;;
    *) verdict "$1" "$2" FAIL "$r" ;;
  esac
}

# build LANG DIR NAME: prints the executable, or returns 1 (reason: failure).
build() {
  lang=$1; dir=$2; name=$3
  : > "$WHYFILE"
  case $lang in
    chez) have_idris || { echo "no Idris toolchain in .toolchain/idris2" > "$WHYFILE"; return 1; } ;;
    mlton) have_mlton || { echo "no MLton in .toolchain/mlton" > "$WHYFILE"; return 1; } ;;
    koka) have_koka || { echo "no Koka (run bench/gate/toolchains.sh)" > "$WHYFILE"; return 1; } ;;
    lean) have_lean || { echo "no Lean (run bench/gate/toolchains.sh)" > "$WHYFILE"; return 1; } ;;
    go) have_go || { echo "no Go (run bench/gate/toolchains.sh)" > "$WHYFILE"; return 1; } ;;
  esac
  "build_$lang" "$dir" "$name" || { echo "the $lang build of $name failed" > "$WHYFILE"; return 1; }
}

# lowered NAME VARIANT: prints the executable of a lowered program, or
# returns 1 (reason: failure).
lowered() {
  : > "$WHYFILE"
  have_llvm || { echo "no pinned MLIR/LLVM tools in .toolchain/llvm" > "$WHYFILE"; return 1; }
  have_snmalloc || { echo "no snmalloc at $SNMALLOC_SRC (third_party/snmalloc)" > "$WHYFILE"; return 1; }
  build_lowered "$1" "$2" || { echo "lowering $1 ($2) failed" > "$WHYFILE"; return 1; }
}

# stats EXE INPUT: runs the stats build once and prints its counters line.
stats() {
  (ulimit -s unlimited 2>/dev/null; printf '%s\n' "$2" | "$1" 2>&1 >/dev/null) | sed -n 's/^idr-stats: //p'
}

col() { if [ -n "$1" ]; then cell "$1" "$2"; else printf 'n/a'; fi; }
secs() { if [ -n "$1" ]; then printf '%.3f s' "$1"; else printf 'n/a'; fi; }
stat_field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }

# same REF OUT: true when the two output files are identical.
same() { cmp -s "$1" "$2"; }

# ---- experiment 1: the suite ---------------------------------------------------

exp_suite() {
  md=$RES/suite.md
  {
    echo "Experiment 1: best of $RUNS, wall-clock seconds and peak RSS."
    echo
    echo "| benchmark | input | Idris Chez | MLton | C | Koka | Lean | outputs |"
    echo "| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |"
  } > "$md"
  for name in $SUITE; do
    dir=$GATE/suite/$name
    input=$(input_of "$name")
    row="| $name | $input |"
    ref=""
    agree="agree"
    for lang in chez mlton c koka lean; do
      if exe=$(build "$lang" "$dir" "$name") && measure suite "$name" "$lang" "$exe" "$input"; then
        row="$row $(cell "$T" "$K") |"
        if [ -z "$ref" ]; then ref=$O
        elif ! same "$ref" "$O"; then
          agree="DIFFER"
          verdict suite "$name: $lang prints what Chez prints" FAIL "$O differs from $ref"
        fi
      else
        row="$row n/a |"
        failure suite "$name in $lang"
      fi
    done
    echo "$row $agree |" >> "$md"
  done
  cat "$md"
}

# ---- experiment 2: hand-lowered code ------------------------------------------

exp_lowered() {
  md=$RES/lowered.md
  {
    echo "Experiment 2: best of $RUNS, wall-clock seconds and peak RSS; live is the"
    echo "prototype's cells left at exit (its stats build)."
    echo
    echo "| program | input | prototype | MLton | Lean | Koka | MLton / prototype | prototype / best of Lean, Koka | live |"
    echo "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
  } > "$md"
  for name in rbtree deriv binarytrees; do
    dir=$GATE/suite/$name
    input=$(input_of "$name")
    ref=""
    if exe=$(build chez "$dir" "$name") && measure lowered "$name" chez "$exe" "$input"; then ref=$O
    elif exe=$(build c "$dir" "$name") && measure lowered "$name" c "$exe" "$input"; then ref=$O
    fi
    tp=""; kp=""; tm=""; km=""; tl=""; tk=""; live="n/a"
    if exe=$(lowered "$name" plain) && measure lowered "$name" prototype "$exe" "$input"; then
      tp=$T; kp=$K
      [ -z "$ref" ] || same "$ref" "$O" ||
        verdict lowered "$name: the prototype prints the reference output" FAIL "$O differs from $ref"
      if sexe=$(lowered "$name" stats); then live=$(stat_field "$(stats "$sexe" "$input")" live); fi
    else
      failure lowered "$name on the prototype"
    fi
    for lang in mlton lean koka; do
      if exe=$(build "$lang" "$dir" "$name") && measure lowered "$name" "$lang" "$exe" "$input"; then
        case $lang in mlton) tm=$T; km=$K ;; lean) tl=$T ;; koka) tk=$T ;; esac
        [ -z "$ref" ] || same "$ref" "$O" ||
          verdict lowered "$name: $lang prints the reference output" FAIL "$O differs from $ref"
      else
        failure lowered "$name in $lang"
      fi
    done
    best=""
    [ -n "$tl" ] && best=$tl
    [ -n "$tk" ] && { [ -z "$best" ] || lt "$tk" "$best"; } && best=$tk
    vs_m=n/a; vs_b=n/a
    [ -n "$tp" ] && [ -n "$tm" ] && vs_m="$(ratio "$tm" "$tp")x"
    [ -n "$tp" ] && [ -n "$best" ] && vs_b="$(ratio "$tp" "$best")"
    echo "| $name | $input | $(col "$tp" "$kp") | $(col "$tm" "$km") | $(secs "$tl") | $(secs "$tk") | $vs_m | $vs_b | $live |" >> "$md"
    # The pass criteria of plan 4.4.
    if [ -n "$tp" ] && [ -n "$tm" ]; then
      if lt "$tp" "$tm"; then verdict lowered "$name faster than MLton" pass "$tp s < $tm s"
      else verdict lowered "$name faster than MLton" FAIL "$tp s >= $tm s"; fi
      if le "$kp" "$km"; then verdict lowered "$name peak memory at most MLton's" pass "$kp KiB <= $km KiB"
      else verdict lowered "$name peak memory at most MLton's" FAIL "$kp KiB > $km KiB"; fi
    else
      verdict lowered "$name against MLton" n/a "a time is missing"
    fi
    if [ -n "$tp" ] && [ -n "$best" ]; then
      lim=$(awk -v b="$best" 'BEGIN { printf "%.3f", 1.2 * b }')
      if le "$tp" "$lim"; then verdict lowered "$name within 1.2x of the better of Lean and Koka" pass "$tp s <= $lim s"
      else verdict lowered "$name within 1.2x of the better of Lean and Koka" FAIL "$tp s > $lim s"; fi
    else
      verdict lowered "$name against Lean and Koka" n/a "a time is missing"
    fi
    [ "$live" = 0 ] || [ "$live" = n/a ] ||
      verdict lowered "$name: the prototype frees every cell" FAIL "live=$live at exit"
  done
  cat "$md"
}

# ---- experiment 3: threads -----------------------------------------------------

exp_threads() {
  md=$RES/threads.md
  {
    echo "Experiment 3: best of $RUNS, wall-clock seconds and peak RSS. The counters"
    echo "come from one run of the prototype's stats build: atomic read-modify-writes"
    echo "on counts, cells marked shared, cells moved."
    echo
    echo "| program | input | prototype | Go | Go / prototype | atomic-rc | marked | moved |"
    echo "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |"
  } > "$md"
  for name in ptrees shmap pipe; do
    input=$(input_of "$name")
    ref=""; tg=""; kg=""; tp=""; kp=""
    if exe=$(build go "$GATE/threads/$name" "$name") && measure threads "$name" go "$exe" "$input"; then
      tg=$T; kg=$K; ref=$O
    else
      failure threads "$name in Go"
    fi
    atom=n/a; marked=n/a; moved=n/a
    if exe=$(lowered "$name" plain) && measure threads "$name" prototype "$exe" "$input"; then
      tp=$T; kp=$K
      [ -z "$ref" ] || same "$ref" "$O" ||
        verdict threads "$name: the prototype prints what Go prints" FAIL "$O differs from $ref"
      if sexe=$(lowered "$name" stats); then
        s=$(stats "$sexe" "$input")
        atom=$(stat_field "$s" atomic-rc); marked=$(stat_field "$s" marked); moved=$(stat_field "$s" moved)
        [ "$(stat_field "$s" live)" = 0 ] ||
          verdict threads "$name: the prototype frees every cell" FAIL "$s"
      fi
    else
      failure threads "$name on the prototype"
    fi
    vs=n/a
    [ -n "$tp" ] && [ -n "$tg" ] && vs="$(ratio "$tg" "$tp")x"
    echo "| $name | $input | $(col "$tp" "$kp") | $(col "$tg" "$kg") | $vs | $atom | $marked | $moved |" >> "$md"
    # Atomics only on genuinely shared data (plan 4.4): nothing is shared in
    # ptrees and pipe; in shmap exactly the map's n cells are.
    if [ "$atom" != n/a ]; then
      case $name in
        ptrees|pipe)
          if [ "$atom" = 0 ] && [ "$marked" = 0 ]; then verdict threads "$name: no atomic count operation, nothing marked" pass "atomic-rc=0 marked=0"
          else verdict threads "$name: no atomic count operation, nothing marked" FAIL "atomic-rc=$atom marked=$marked"; fi ;;
        shmap)
          set -- $input
          if [ "$marked" = "$1" ]; then verdict threads "shmap: exactly the map's $1 cells marked shared" pass "marked=$marked atomic-rc=$atom"
          else verdict threads "shmap: exactly the map's $1 cells marked shared" FAIL "marked=$marked"; fi ;;
      esac
    else
      verdict threads "$name counters" n/a "no stats build"
    fi
    if [ -n "$tp" ] && [ -n "$tg" ]; then
      if le "$tp" "$tg"; then verdict threads "$name no slower than Go" pass "$tp s <= $tg s"
      else verdict threads "$name no slower than Go" FAIL "$tp s > $tg s"; fi
    else
      verdict threads "$name against Go" n/a "a time is missing"
    fi
  done
  # The open parameters of plan 12.2 item 8, measured on the pipeline:
  # flushing remote frees at the end of each turn, and dead roots sent home.
  {
    echo
    echo "The pipeline under the runtime's variants (plan 5.6, 12.2 item 8):"
    echo
    echo "| variant | time, peak RSS |"
    echo "| --- | ---: |"
  } >> "$md"
  input=$(input_of pipe)
  for v in plain flush home flush-home; do
    if exe=$(lowered pipe "$v") && measure threads "pipe-$v" prototype "$exe" "$input"; then
      echo "| $v | $(cell "$T" "$K") |" >> "$md"
    else
      echo "| $v | n/a |" >> "$md"
    fi
  done
  cat "$md"
}

# ---- experiment 4: the linear red-black tree ----------------------------------

# A diagnostic that a build log gives about the file SRC.
diagnostic() { grep -i -E 'warning|error' "$1" 2>/dev/null | grep -F "$2" || true; }

exp_linear() {
  md=$RES/linear.md
  input=$(input_of linrb)
  {
    echo "Experiment 4: best of $RUNS, wall-clock seconds and peak RSS; input $input."
    echo "\"shared\" is the program with the one call site that keeps a second"
    echo "reference (bench/gate/linear/linrb-shared)."
    echo
    echo "| version | unique | shared | shared / unique |"
    echo "| --- | ---: | ---: | ---: |"
  } > "$md"
  ref=""
  if exe=$(build chez "$GATE/linear/linrb" linrb) && measure linear linrb chez "$exe" "$input"; then
    ref=$O; tu=$T; ku=$K
    if exe=$(build chez "$GATE/linear/linrb-shared" linrb-shared) && measure linear linrb-shared chez "$exe" "$input"; then
      same "$ref" "$O" || verdict linear "linrb-shared prints what linrb prints (Chez)" FAIL "$O differs"
      echo "| Idris Chez (baseline) | $(cell "$tu" "$ku") | $(cell "$T" "$K") | $(ratio "$T" "$tu") |" >> "$md"
    fi
  else
    failure linear "linrb on Chez"
  fi
  # The prototype: static reuse (MEM-LIN-1) against dynamic reuse.
  ts=""; td=""
  for v in static dynamic; do
    if exe=$(lowered "linrb-$v" plain) && measure linear "linrb-$v" prototype "$exe" "$input"; then
      case $v in static) ts=$T; ks=$K ;; dynamic) td=$T; kd=$K ;; esac
      [ -z "$ref" ] || same "$ref" "$O" ||
        verdict linear "linrb-$v prints the reference output" FAIL "$O differs from $ref"
      if sexe=$(lowered "linrb-$v" stats); then
        s=$(stats "$sexe" "$input")
        set -- $input
        cells=$(stat_field "$s" cells)
        if [ "$cells" = "$1" ] && [ "$(stat_field "$s" live)" = 0 ]; then
          verdict linear "linrb-$v: full reuse, one cell per insert" pass "cells=$cells live=0"
        else
          verdict linear "linrb-$v: full reuse, one cell per insert" FAIL "$s"
        fi
      fi
    else
      failure linear "linrb-$v on the prototype"
    fi
  done
  if [ -n "$ts" ] && [ -n "$td" ]; then
    echo "| prototype, static reuse | $(cell "$ts" "$ks") | rejected (MEM-LIN-1) | |" >> "$md"
    echo "| prototype, dynamic reuse | $(cell "$td" "$kd") | | |" >> "$md"
    if le "$ts" "$td"; then verdict linear "static reuse at least as fast as dynamic" pass "$ts s <= $td s"
    else verdict linear "static reuse at least as fast as dynamic" FAIL "$ts s > $td s"; fi
  else
    verdict linear "static against dynamic" n/a "a time is missing"
  fi
  # The cliff: Koka and Lean compile the broken call site silently, and
  # every insert copies its path.
  for lang in koka lean; do
    if ue=$(build "$lang" "$GATE/linear/linrb" linrb) && measure linear linrb "$lang" "$ue" "$input"; then
      tu=$T; ku=$K
      [ -z "$ref" ] || same "$ref" "$O" || verdict linear "linrb in $lang prints the reference output" FAIL "$O differs"
      if se=$(build "$lang" "$GATE/linear/linrb-shared" linrb-shared) && measure linear linrb-shared "$lang" "$se" "$input"; then
        [ -z "$ref" ] || same "$ref" "$O" || verdict linear "linrb-shared in $lang prints the reference output" FAIL "$O differs"
        slow=$(ratio "$T" "$tu")
        echo "| $lang | $(cell "$tu" "$ku") | $(cell "$T" "$K") | $slow |" >> "$md"
        src=linrb-shared.kk; [ "$lang" = lean ] && src=linrb_shared.lean
        diag=$(diagnostic "$se.log" "$src")
        if [ -n "$diag" ]; then
          verdict linear "$lang: the broken call site gets no diagnostic" FAIL "$diag"
        elif le "$CLIFF" "$slow"; then
          verdict linear "$lang: a silent cliff, slowdown of at least ${CLIFF}x" pass "${slow}x, no diagnostic"
        else
          verdict linear "$lang: a silent cliff, slowdown of at least ${CLIFF}x" FAIL "only ${slow}x"
        fi
      else
        failure linear "linrb-shared in $lang"
      fi
    else
      failure linear "linrb in $lang"
    fi
  done
  cat "$md"
}

# ---- main --------------------------------------------------------------------

[ $# -gt 0 ] || set -- suite lowered threads linear
build_measure
: > "$TSV"
: > "$VERDICTS"
for e in "$@"; do
  case $e in
    suite) exp_suite ;;
    lowered) exp_lowered ;;
    threads) exp_threads ;;
    linear) exp_linear ;;
    *) die "unknown experiment $e (suite, lowered, threads or linear)" ;;
  esac
  echo
done
echo "Verdicts: $VERDICTS"
if [ "$FAILED" = 1 ]; then echo "gate: FAIL"; exit 1; fi
if [ "$MISSING" = 1 ]; then echo "gate: INCOMPLETE (see n/a above)"; exit 2; fi
echo "gate: PASS"
