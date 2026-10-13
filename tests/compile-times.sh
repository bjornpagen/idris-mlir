#!/bin/sh
# The compile times the golden tests recorded (tests/lib/timing.sh,
# `record_time`), each compilation broken down by idris-mlir's timing
# report into the parse, idr-simplify with its round count, the verifier,
# the analyses, LLVM and the rest; with --against, what changed since an
# earlier record of the same breakdown. It reports; it gates nothing.
#
#     tests/compile-times.sh [--timing DIR] [--record FILE] [--against OLD-FILE]
#     tests/compile-times.sh --tree MODULE
#
# The test records are in DIR (tests/build/timing), where every run of
# `make test` (and of the other suites that compile) leaves one file per
# test: `<ms> TAB <exit> TAB <what> TAB <module>` per compilation, the
# module being the .mlir Emit wrote, kept so that it can be compiled again
# here.
#
# Each compilation that succeeded and kept its module is compiled again,
# alone, with `idris-mlir -c MODULE -o OBJECT` and the options it was
# recorded with, under MLIR's timing in its tree display and its JSON
# output (--mlir-timing --mlir-timing-display=tree
# --mlir-output-format=json). In that report a row is one line, a JSON
# object with its "wall" duration and its "name"; a row with rows inside
# it opens a "passes" list that a line of its own closes. A row's name is
# MLIR's: a pass's name (IdrSimplify), a nested pipeline's, an analysis's
# with `(A) ` before it, VerifierPass for each verification, and the
# driver's own rows (parse, LLVM) at the top. The columns, in seconds of
# wall time:
#
#     total     the report's Total
#     parse     the top-level parse row
#     simplify  the idr-simplify rows (IdrSimplify), everything inside
#               them included
#     verify    every VerifierPass row, inside idr-simplify or not
#     analyses  every analysis row not inside another analysis row
#     llvm      the top-level LLVM row
#     rest      total less parse, simplify, llvm, and the verify and
#               analyses rows outside idr-simplify
#
# The rounds are the simplify loop's, read off its fixpoint remark
# (`fixpoint: round N changed nothing`), from idris-mlir-opt running the
# pipeline on the same module (--idr-target --idr-pipeline
# --remarks-filter-passed=idr-simplify): the driver prints no remarks. A
# compilation whose report or remark is missing shows n/a in that column.
#
# Everything measured goes to FILE (tests/build/compile-times.tsv), one
# line per compilation: `<test> TAB <n> TAB <what> TAB <recorded ms> TAB
# <total> TAB <parse> TAB <simplify> TAB <rounds> TAB <verify> TAB
# <analyses> TAB <llvm> TAB <rest>`, the nth compilation of the test. The
# report on stdout gives the sum of each column, the ten slowest
# compilations, and the rounds: how many compilations took each count, and
# the ten that took the most.
#
# --against OLD-FILE compares with a FILE this script wrote earlier: a
# compilation of the same test, the same compilation of its run, in both.
# It prints each column's sum then and now, the ten whose total grew the
# most among those that took a second or more in either, every compilation
# that now takes over twice its earlier total (one of those is a bug of
# ours, fixed before the change is done), and every compilation whose
# round count grew. The times are wall times under the load of the machine
# that measured them, so compare records taken alike, on the same machine.
#
# The record of the build before a change is taken before the change is
# first built, while build/ and DIR are still that build's: copy DIR away
# (`cp -Rp tests/build/timing tests/build/timing-before`, after a full
# `make test` of that build), then
#
#     tests/compile-times.sh --timing tests/build/timing-before \
#       --record tests/build/compile-times-before.tsv
#
# with that build's tools still in build/; after the change's `make build`
# and `make test`,
#
#     tests/compile-times.sh --against tests/build/compile-times-before.tsv
#
# The parse and LLVM rows, idr-simplify's and VerifierPass's are named
# alike in both builds, wherever the pipeline nests them, so the columns
# compare across a change of the pipeline's shape.
#
# --tree MODULE reads one compilation's report as a tree, under MLIR's pool
# and under one thread (--mlir-disable-threading), wall time against user
# time, for what a change of the pipeline is measured by on a large
# program (programs/prelude/every-interfaces-export's module):
#
#   - where each analysis is computed: every `(A)` row inside idr-simplify
#     with the passes around it, and those outside their place, an
#     analysis row being in its place under the pass nearest it that is no
#     analysis: References under idr-effects, idr-inline or
#     idr-specialize, Effects under idr-effects, Identities under
#     idr-round-facts, CloneTable and BindingTimes under idr-round-facts or
#     idr-specialize; and, anywhere, every `(A)` row under a function
#     pass, which computes no analysis;
#   - the verifier: the VerifierPass rows inside idr-simplify, and the one
#     after idr-rc, each against the total;
#   - the serial residue of the round: idr-simplify's own time (its row
#     less the rows inside it), its VerifierPass rows' wall against user
#     time, and its (A) CallGraph rows, each against idr-simplify's;
#   - the Canonicalizer and CSE rows inside idr-inline.
#
# MLIR's timing merges the rows of one pass's runs, so a round's rows are
# the sum over the rounds; the round count is the fixpoint remark's.

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"

usage() {
  echo "usage: $0 [--timing DIR] [--record FILE] [--against OLD-FILE]" >&2
  echo "       $0 --tree MODULE" >&2
  exit 2
}
top=10
dir=$root/tests/build/timing
record=$root/tests/build/compile-times.tsv
against=
tree=
while [ $# -gt 0 ]; do
  case $1 in
    --timing) [ $# -ge 2 ] || usage; dir=$2; shift ;;
    --record) [ $# -ge 2 ] || usage; record=$2; shift ;;
    --against) [ $# -ge 2 ] || usage; against=$2; shift ;;
    --tree) [ $# -ge 2 ] || usage; tree=$2; shift ;;
    *) usage ;;
  esac
  shift
done

set -- "$dir"/*.tsv
if [ -z "$tree" ] && [ ! -f "$1" ]; then
  echo "no timing records in $dir: run make test first" >&2
  exit 1
fi
if [ -n "$tree" ] && [ ! -f "$tree" ]; then
  echo "no module $tree" >&2
  exit 1
fi
if [ -n "$against" ] && [ ! -f "$against" ]; then
  echo "no compile-time record $against" >&2
  exit 1
fi
if [ ! -x "$idris_mlir" ] || [ ! -x "$idris_mlir_opt" ]; then
  echo "no idris-mlir or idris-mlir-opt under $dev_prefix: run make build first" >&2
  exit 1
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idris-mlir-times.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM
tab=$(printf '\t')

# limited CMD...: CMD, ended after ten minutes, so that a compilation that
# no longer finishes shows as n/a instead of stopping the report.
limited() {
  if [ -n "$timeout_cmd" ]; then
    "$timeout_cmd" -k 5 600 "$@"
  else
    "$@"
  fi
}

# breakdown REPORT: the columns of an idris-mlir timing report in MLIR's
# JSON tree output, as `<total> <parse> <simplify> <verify> <analyses>
# <llvm> <rest>`, or nothing when it holds no Total.
breakdown() {
  awk '
    function wall(line,   s) {
      if (!match(line, /"wall": *\{ *"duration": *-?[0-9.]+/)) return 0
      s = substr(line, RSTART, RLENGTH)
      sub(/.*: */, "", s)
      return s + 0
    }
    /"name": *"/ {
      name = $0
      sub(/.*"name": *"/, "", name)
      sub(/".*/, "", name)
      w = wall($0)
      key = tolower(name)
      gsub(/-/, "", key)
      kind = "other"
      if (depth == 0 && key == "total") total = w
      else if (depth == 0 && (key == "parse" || key == "parser")) parse += w
      else if (depth == 0 && key == "llvm") llvm += w
      else if (key == "idrsimplify" && insimplify == 0) { simplify += w; kind = "simplify" }
      else if (name == "VerifierPass") {
        verify += w
        if (insimplify == 0) outside += w
      } else if (substr(name, 1, 4) == "(A) " && inanalysis == 0) {
        analyses += w
        if (insimplify == 0) outside += w
        kind = "analysis"
      }
      if ($0 ~ /"passes": *\[/) {
        depth++
        kinds[depth] = kind
        if (kind == "simplify") insimplify++
        if (substr(name, 1, 4) == "(A) ") inanalysis++
        named[depth] = name
      }
      next
    }
    /^[ \t]*(\{\})?\][}],?[ \t]*$/ {
      if (depth > 0) {
        if (kinds[depth] == "simplify") insimplify--
        if (substr(named[depth], 1, 4) == "(A) ") inanalysis--
        depth--
      }
    }
    END {
      if (total == "") exit
      printf "%.4f %.4f %.4f %.4f %.4f %.4f %.4f\n", total, parse, simplify, verify, analyses,
        llvm, total - parse - simplify - llvm - outside
    }' "$1"
}

# rounds MODULE: the simplify loop's round count on MODULE, or nothing.
rounds() {
  limited "$idris_mlir_opt" "$1" --idr-target --idr-pipeline \
    --remarks-filter-passed=idr-simplify -o /dev/null > "$tmp/rounds.out" 2> "$tmp/rounds.err"
  grep -ho 'round [0-9][0-9]* changed nothing' "$tmp/rounds.out" "$tmp/rounds.err" |
    tail -n 1 | awk '{ print $2 }'
}

# rows REPORT: the rows of a JSON tree report, one per line, as `<id> TAB
# <parent id> TAB <name> TAB <wall> TAB <user>`, the report's own rows
# (and Total) under parent 0; user is wall where the report gives none.
rows() {
  awk '
    function duration(line, what,   s) {
      if (!match(line, "\"" what "\": *\\{ *\"duration\": *-?[0-9.]+")) return ""
      s = substr(line, RSTART, RLENGTH)
      sub(/.*: */, "", s)
      return s + 0
    }
    /"name": *"/ {
      name = $0
      sub(/.*"name": *"/, "", name)
      sub(/".*/, "", name)
      w = duration($0, "wall")
      u = duration($0, "user")
      if (u == "") u = w
      id++
      printf "%d\t%d\t%s\t%s\t%s\n", id, (depth ? open[depth] : 0), name, w, u
      if ($0 ~ /"passes": *\[/) open[++depth] = id
      next
    }
    /^[ \t]*(\{\})?\][}],?[ \t]*$/ { if (depth > 0) depth-- }' "$1"
}

# tree_report ROWS LABEL: what --tree prints of the rows ROWS, under LABEL.
tree_report() {
  awk -F'\t' -v label="$2" '
    function key(name,   k) { k = tolower(name); gsub(/-/, "", k); return k }
    function analysis(i) { return substr(name[i], 1, 4) == "(A) " }
    function short(i,   s) { s = substr(name[i], 5); sub(/.*::/, "", s); return s }
    function path(i,   s) {
      s = name[i]
      for (i = parent[i]; i > 0; i = parent[i]) s = name[i] " > " s
      return s
    }
    function within(i, k) {
      for (i = parent[i]; i > 0; i = parent[i]) if (key(name[i]) == k) return 1
      return 0
    }
    function nearest(i) {
      for (i = parent[i]; i > 0 && analysis(i); i = parent[i]) {}
      return i
    }
    function underFunctionPass(i) {
      for (i = parent[i]; i > 0; i = parent[i])
        if (name[i] ~ /^'\''[^'\'']*'\'' Pipeline$/ && name[i] !~ /^'\''builtin\.module'\''/) return 1
      return 0
    }
    {
      n = $1; parent[n] = $2; name[n] = $3; wall[n] = $4; user[n] = $5
      children[$2] = children[$2] " " n
      if ($3 == "Total" && $2 == 0) total = $4
      if (key($3) == "idrsimplify" && simplify == "") simplify = n
    }
    END {
      allowed["References"] = " idreffects idrinline idrspecialize "
      allowed["Effects"] = " idreffects "
      allowed["Identities"] = " idrroundfacts "
      allowed["CloneTable"] = " idrroundfacts idrspecialize "
      allowed["BindingTimes"] = " idrroundfacts idrspecialize "
      printf "%s: Total %.4f s wall\n\n", label, total
      printf "Analyses inside idr-simplify, wall against user s:\n\n"
      for (i = 1; i <= n; i++) {
        if (!analysis(i)) continue
        inside = simplify != "" && within(i, "idrsimplify")
        p = nearest(i)
        out = 0
        if (underFunctionPass(i)) out = 1
        else if (inside && (short(i) in allowed) && index(allowed[short(i)], " " key(name[p]) " ") == 0) out = 1
        if (inside) printf "- %s: %.4f / %.4f%s\n", path(i), wall[i], user[i], (out ? "  OUTSIDE ITS PLACE" : "")
        else if (out) printf "- %s: %.4f / %.4f  OUTSIDE ITS PLACE\n", path(i), wall[i], user[i]
        if (out) misplaced++
      }
      printf "\n%d analysis rows outside their place.\n\n", misplaced
      if (simplify == "") { print "No idr-simplify row."; exit }
      inner = 0; verify = 0; verifyUser = 0; callgraph = 0
      m = split(children[simplify], kids, " ")
      for (j = 1; j <= m; j++) inner += wall[kids[j]]
      for (i = 1; i <= n; i++) {
        if (!within(i, "idrsimplify")) continue
        if (name[i] == "VerifierPass") { verify += wall[i]; verifyUser += user[i] }
        if (analysis(i) && short(i) == "CallGraph") callgraph += wall[i]
      }
      s = wall[simplify]
      printf "idr-simplify: %.4f s wall, %.4f s user\n", s, user[simplify]
      printf "- its own time: %.4f s (%.1f%% of it)\n", s - inner, (s > 0 ? 100 * (s - inner) / s : 0)
      printf "- VerifierPass rows: %.4f s wall, %.4f s user (%.1f%% of it, %.1f%% of Total)\n",
        verify, verifyUser, (s > 0 ? 100 * verify / s : 0), (total > 0 ? 100 * verify / total : 0)
      printf "- (A) CallGraph rows: %.4f s (%.1f%% of it)\n", callgraph, (s > 0 ? 100 * callgraph / s : 0)
      # The VerifierPass row after idr-rc: the sibling that follows it.
      for (i = 1; i <= n; i++) {
        if (key(name[i]) != "idrrc") continue
        m = split(children[parent[i]], kids, " ")
        for (j = 1; j < m; j++)
          if (kids[j] == i && name[kids[j + 1]] == "VerifierPass")
            printf "VerifierPass after idr-rc: %.4f s wall, %.4f s user (%.1f%% of Total)\n",
              wall[kids[j + 1]], user[kids[j + 1]], (total > 0 ? 100 * wall[kids[j + 1]] / total : 0)
      }
      printf "\nInside idr-inline:\n"
      for (i = 1; i <= n; i++)
        if ((name[i] == "Canonicalizer" || name[i] == "CSE") && within(i, "idrinline"))
          printf "- %s: %.4f s wall, %.4f s user\n", path(i), wall[i], user[i]
    }' "$1"
}

if [ -n "$tree" ]; then
  round=$(rounds "$tree")
  echo "$tree: ${round:-n/a} rounds of the simplify loop."
  for threads in pool one; do
    flags=
    [ "$threads" = one ] && flags=--mlir-disable-threading
    # shellcheck disable=SC2086 # empty or one flag
    limited "$idris_mlir" -c "$tree" -o "$tmp/object.o" $flags --mlir-timing \
      --mlir-timing-display=tree --mlir-output-format=json > "$tmp/report" 2>&1
    rows "$tmp/report" > "$tmp/rows"
    echo
    if [ -s "$tmp/rows" ]; then
      tree_report "$tmp/rows" "under $( [ "$threads" = one ] && echo one thread || echo the pool )"
    else
      echo "under $threads: no timing report"
      head -n 20 "$tmp/report"
    fi
  done
  exit 0
fi

# The records: `<ms> TAB <test> TAB <exit> TAB <what> TAB <module> TAB <n>`
# for each compilation, the nth of its test.
for file in "$dir"/*.tsv; do
  [ -f "$file" ] || continue
  test=${file##*/}
  test=$(printf '%s' "${test%.tsv}" | sed 's|__|/|g')
  awk -F'\t' -v test="$test" \
    'NF >= 4 { print $1 "\t" test "\t" $2 "\t" $3 "\t" $4 "\t" FNR }' "$file"
done > "$tmp/records"

count=$(wc -l < "$tmp/records" | tr -d ' ')
echo "$count compilations recorded in $dir; each that succeeded is measured again." >&2
mkdir -p "$(dirname "$record")"
: > "$tmp/record"
while IFS="$tab" read -r ms test status what module n; do
  [ "$status" = 0 ] && [ "$module" != - ] && [ -f "$module" ] || continue
  # The options it was recorded with, but `compile`, the word the record
  # starts with.
  options=${what#compile}
  # shellcheck disable=SC2086 # the options are words
  limited "$idris_mlir" -c "$module" -o "$tmp/object.o" $options --mlir-timing \
    --mlir-timing-display=tree --mlir-output-format=json > "$tmp/report" 2>&1
  columns=$(breakdown "$tmp/report")
  [ -n "$columns" ] || columns='n/a n/a n/a n/a n/a n/a n/a'
  round=$(rounds "$module")
  [ -n "$round" ] || round=n/a
  # shellcheck disable=SC2086 # the columns are words
  set -- $columns
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$test" "$n" "$what" "$ms" "$1" "$2" "$3" "$round" "$4" "$5" "$6" "$7" >> "$tmp/record"
done < "$tmp/records"
cp "$tmp/record" "$record"

measured=$(wc -l < "$record" | tr -d ' ')
echo "$measured compilations measured, recorded in $record."
echo
awk -F'\t' '
  function add(i, v) { if (v != "n/a") sum[i] += v }
  { for (i = 5; i <= 12; i++) if (i != 8) add(i, $i) }
  END {
    printf "| s in all | total | parse | idr-simplify | verify | analyses | LLVM | rest |\n"
    printf "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n"
    printf "| %d compilations | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f |\n",
      NR, sum[5], sum[6], sum[7], sum[9], sum[10], sum[11], sum[12]
  }' "$record"

echo
echo "The $top slowest, by idris-mlir -c's total:"
echo
echo "| test | compilation | recorded s | total s | parse s | idr-simplify s | rounds | verify s | analyses s | LLVM s | rest s |"
echo "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
awk -F'\t' '$5 != "n/a"' "$record" | sort -t "$tab" -k5,5gr | head -n "$top" |
  awk -F'\t' '{ printf "| %s | %s | %.3f | %s | %s | %s | %s | %s | %s | %s | %s |\n",
    $1, $3, $4 / 1000, $5, $6, $7, $8, $9, $10, $11, $12 }'

echo
echo "The rounds: how many compilations took each count."
echo
echo "| rounds | compilations |"
echo "| ---: | ---: |"
cut -f 8 "$record" | sort | uniq -c | sort -k2,2n | awk '{ printf "| %s | %d |\n", $2, $1 }'
echo
echo "The $top that took the most rounds:"
echo
echo "| test | compilation | rounds | idr-simplify s |"
echo "| --- | --- | ---: | ---: |"
awk -F'\t' '$8 != "n/a"' "$record" | sort -t "$tab" -k8,8nr | head -n "$top" |
  awk -F'\t' '{ printf "| %s | %s | %s | %s |\n", $1, $3, $8, $7 }'

[ -n "$against" ] || exit 0
# `<test> TAB <n> TAB <what>`, then each column then and now, for each
# compilation in both, the same compilation of the same test.
awk -F'\t' '
  NR == FNR { old[$1 "\t" $2 "\t" $3] = $0; next }
  ($1 "\t" $2 "\t" $3) in old {
    split(old[$1 "\t" $2 "\t" $3], o, "\t")
    line = $1 "\t" $2 "\t" $3
    for (i = 4; i <= 12; i++) line = line "\t" o[i] "\t" $i
    print line
  }' "$against" "$record" > "$tmp/pairs"
# In $tmp/pairs, the column c of the record (4 to 12) is then at 2c - 4
# and now at 2c - 3.
echo
awk -F'\t' -v against="$against" '
  function add(i, v) { if (v != "n/a") sum[i] += v }
  { for (c = 5; c <= 12; c++) if (c != 8) { add("then" c, $(2 * c - 4)); add("now" c, $(2 * c - 3)) } }
  END {
    printf "Against %s: %d compilations in both.\n\n", against, NR
    printf "| s in all | total | parse | idr-simplify | verify | analyses | LLVM | rest |\n"
    printf "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n"
    printf "| then | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f |\n",
      sum["then5"], sum["then6"], sum["then7"], sum["then9"], sum["then10"], sum["then11"], sum["then12"]
    printf "| now | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f |\n",
      sum["now5"], sum["now6"], sum["now7"], sum["now9"], sum["now10"], sum["now11"], sum["now12"]
  }' "$tmp/pairs"

# `<ratio> TAB <test> TAB <what> TAB <then> TAB <now>` of the totals, for
# the compilations measured in both.
awk -F'\t' '$6 != "n/a" && $7 != "n/a" && $6 > 0 {
  printf "%.3f\t%s\t%s\t%s\t%s\n", $7 / $6, $1, $3, $6, $7 }' "$tmp/pairs" > "$tmp/ratios"
echo
echo "The $top whose total grew the most, of those that took a second or more:"
echo
echo "| test | compilation | then s | now s | now/then |"
echo "| --- | --- | ---: | ---: | ---: |"
awk -F'\t' '$4 >= 1 || $5 >= 1' "$tmp/ratios" | sort -t "$tab" -k1,1gr | head -n "$top" |
  awk -F'\t' '{ printf "| %s | %s | %s | %s | %.2f |\n", $2, $3, $4, $5, $1 }'
echo
echo "Over twice their earlier total:"
echo
awk -F'\t' '$1 > 2 { printf "- %s (%s): %s s then, %s s now\n", $2, $3, $4, $5; n++ }
  END { if (n == 0) print "none" }' "$tmp/ratios"
echo
echo "Whose round count grew:"
echo
# The rounds are the record's column 8: then at 12, now at 13.
awk -F'\t' '$12 != "n/a" && $13 != "n/a" && $13 + 0 > $12 + 0 {
    printf "- %s (%s): %s rounds then, %s now\n", $1, $3, $12, $13; n++ }
  END { if (n == 0) print "none" }' "$tmp/pairs"
