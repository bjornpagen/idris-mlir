#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Every file of the tree names its licence at its head, in its kind's
# comment syntax: its first line, or the line after a script's #!, with its
# copyright holder on the next. Ours is 0BSD, and ours is its holder. The
# type checker's, Idris's checker copied into compiler/checker, is
# BSD-3-Clause, and each of its files names its own holder: Idris's (Edwin
# Brady and the Idris contributors) on a file copied from Idris, ours on
# one written here. This script is the one place that knows the scope,
# which is every file git tracks or would track, less the exclusions
# below, each with its reason: a file of a new kind is in scope at once,
# and named until its kind's comment syntax is here.
#
#   tools/licenses.sh           check: name every file in scope without its
#                               lines, or with a wrong one; exit 1 if any
#   tools/licenses.sh --apply   write the missing lines, ours (a file with
#                               none was written here), and correct the
#                               holder of a part that has one; a holder a
#                               file names itself is never written
#
# Besides: the text of every licence an identifier in use names is in
# LICENSES/.
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1

apply=0
[ "${1:-}" = --apply ] && apply=1

work=$(mktemp -d "${TMPDIR:-/tmp}/idris-mlir-licenses.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT

# What is not in scope: `patterns -- reason`, each pattern a shell pattern
# of a path from the root, in which `*` matches across directories.
exclusions() {
  cat << 'EOF'
third_party/* -- the pinned submodules: their parties' trees, untouched
sources/* -- the research library: each item is its party's, its provenance beside it
.claude/* -- the agent harness's configuration, whose front matter must open each file
.gitmodules -- git's record of the submodules, which git submodule writes
LICENSE LICENSES/*.txt compiler/checker/LICENSE -- the licence texts themselves
NOTICE -- the attribution notices, which quote the parties' own
*.json *.tsv *.svg -- a kind with no comment syntax
foreign/idr/generated.manifest -- the generated files' fingerprints, one `hash path` line each, which the specification's generator writes and checks
*.patch *.diff -- a patch or a diff, every line of which is applied
*/expected */expected-* */expected.* *.check *.expect *.expected -- what a test compares its output with
*/stdin */input */input-from *.in *.out -- what a test or a benchmark reads, byte for byte
*/packages */covers */heap-free */libm-lines */targets */suite */about -- a mark or a datum of a fixture or a benchmark, which its harness reads
*/allowlist */allowed */uncovered */without-fixture -- a list a spec test reads
tests/*/*.idr tests/*.mlir tests/*.ll -- a fixture's source, whose line numbers reach its expected output
upstream/*/*.mlir upstream/*/*.ll upstream/*/*.sh upstream/*/*.idr upstream/*/*.c upstream/*/*.cpp -- a reproducer, which its report quotes and its upstream test copies
tests/licenses/witness/* -- the files tests/licenses plants for this check to refuse, each without its line or with a wrong one
bench/records/* -- a record of a measurement, kept as it was taken
EOF
}

# The comment syntax of each kind: `patterns -- open [close]`. A file of no
# kind listed that starts with #! is a script, whose comments open with #.
kinds() {
  cat << 'EOF'
*.md -- <!-- -->
*.idr *.ipkg -- --
*.c *.cc *.cpp *.h *.hpp *.inc *.td -- //
*.sh */run *.py *.txt *.yml *.yaml *.toml Makefile */Makefile CMakeLists.txt */CMakeLists.txt .gitignore .editorconfig .clang-tidy -- #
EOF
}

ours='2026 Bjorn Pagen'

# The parts of the tree: `patterns -- identifier [holder]`, the first that
# matches. A part with a holder is that holder's in every file. A part
# without one is a tree of several holders, each file naming its own on its
# copyright line, `Copyright (c) <years> <holder>`: the checker's, which
# holds Idris's files and ours.
parts() {
  cat << EOF
compiler/checker/* -- BSD-3-Clause
* -- 0BSD $ours
EOF
}

git -c core.quotePath=false ls-files -co --exclude-standard | LC_ALL=C sort -u > "$work/tree"
exclusions > "$work/exclusions"
kinds > "$work/kinds"
parts > "$work/parts"

# Each file in scope, read at its head: `what TAB file TAB ...`, where what
# is ok, missing (TAB the line the header goes at TAB open TAB close TAB
# identifier TAB holder), holder (TAB its line TAB the line it should be),
# unnamed (TAB the line that names no holder), wrong (TAB the expression
# TAB the identifier) or nokind; and an `id TAB identifier` line for each
# identifier a file in scope names.
awk -F'\t' -v ours="$ours" '
  # A shell pattern as an anchored regular expression.
  function glob(p,   out, j, c) {
    out = "^"
    for (j = 1; j <= length(p); j++) {
      c = substr(p, j, 1)
      if (c == "*") out = out ".*"
      else if (c == "?") out = out "."
      else if (c ~ /[.+^$|(){}\[\]\\]/) out = out "\\" c
      else out = out c
    }
    return out "$"
  }
  # The patterns and the rest of a `patterns -- rest` line, into pat[] and
  # the returned rest.
  function split_rule(line,   at, n, j, words) {
    at = index(line, " -- ")
    n = split(substr(line, 1, at - 1), words, " ")
    npat = 0
    for (j = 1; j <= n; j++) pat[++npat] = glob(words[j])
    return substr(line, at + 4)
  }
  FILENAME == ARGV[1] { split_rule($0); for (j = 1; j <= npat; j++) excluded[++ne] = pat[j]; next }
  FILENAME == ARGV[2] {
    rest = split_rule($0)
    for (j = 1; j <= npat; j++) { nk++; kind[nk] = pat[j]; syntax[nk] = rest }
    next
  }
  FILENAME == ARGV[3] {
    rest = split_rule($0)
    sp = index(rest, " ")
    for (j = 1; j <= npat; j++) {
      np++; part[np] = pat[j]
      ident[np] = sp == 0 ? rest : substr(rest, 1, sp - 1)
      owner[np] = sp == 0 ? "" : substr(rest, sp + 1)
    }
    next
  }
  {
    f = $0
    for (j = 1; j <= ne; j++) if (f ~ excluded[j]) next
    n = 0; r = 1
    while (n < 3 && (r = (getline text < f)) > 0) line[++n] = text
    close(f)
    if (r < 0) next
    for (j = n + 1; j <= 3; j++) line[j] = ""
    at = substr(line[1], 1, 2) == "#!" ? 2 : 1
    open = ""; shut = ""
    for (j = 1; j <= nk; j++) if (f ~ kind[j]) { split(syntax[j], s, " "); open = s[1]; shut = s[2]; break }
    if (open == "" && at == 2) open = "#"
    for (j = 1; j <= np; j++) if (f ~ part[j]) { id = ident[j]; holder = owner[j]; break }
    head = line[at]
    k = index(head, "SPDX-License-Identifier: ")
    if (k == 0) {
      # A file without its lines was written here, since one copied from
      # another party arrives with its own: its holder is the one of its
      # part, or ours.
      if (open == "") print "nokind\t" f
      else print "missing\t" f "\t" at "\t" open "\t" shut "\t" id "\t" (holder == "" ? ours : holder)
      next
    }
    expr = substr(head, k + 25)
    sub(/[ \t]+$/, "", expr)
    if (shut != "" && substr(expr, length(expr) - length(shut) + 1) == shut)
      expr = substr(expr, 1, length(expr) - length(shut))
    sub(/[ \t]+$/, "", expr)
    m = split(expr, tokens, /[ ()]+/)
    for (j = 1; j <= m; j++)
      if (tokens[j] != "" && tokens[j] != "AND" && tokens[j] != "OR" && tokens[j] != "WITH")
        print "id\t" tokens[j]
    if (expr != id) { print "wrong\t" f "\t" expr "\t" id; next }
    lead = substr(head, 1, k - 1) "Copyright (c) "
    tail = shut == "" ? "" : " " shut
    named = line[at + 1]
    if (holder != "") {
      if (named != lead holder tail) { print "holder\t" f "\t" at + 1 "\t" lead holder tail; next }
    } else {
      # The file names its holder: its years, then the holder.
      notice = substr(named, length(lead) + 1, length(named) - length(lead) - length(tail))
      if (substr(named, 1, length(lead)) != lead || substr(named, length(named) - length(tail) + 1) != tail ||
          notice !~ /^[0-9][0-9][0-9][0-9]( ?[-,] ?[0-9][0-9][0-9][0-9])* +[^ ]/) {
        print "unnamed\t" f "\t" at + 1
        next
      }
    }
    print "ok\t" f
  }' "$work/exclusions" "$work/kinds" "$work/parts" "$work/tree" > "$work/found"

bad=0
# report KIND MESSAGE: each file found of that kind, with the message.
report() {
  awk -F'\t' -v kind="$1" -v message="$2" '$1 == kind { print $2 ": " message }' "$work/found" > "$work/report"
  if [ -s "$work/report" ]; then
    cat "$work/report"
    bad=1
  fi
}
report nokind "no comment syntax known for its kind: add it here, or exclude it with a reason"
awk -F'\t' '$1 == "wrong" { print $2 ": names " $3 ", where its part is " $4 }' "$work/found" > "$work/report"
[ -s "$work/report" ] && { cat "$work/report"; bad=1; }
# Whose a file is that names its own holder only the file can say, so a
# line naming none is never written here.
awk -F'\t' '$1 == "unnamed" { print $2 ": line " $3 " names no holder, as Copyright (c) <years> <holder>" }' "$work/found" > "$work/report"
[ -s "$work/report" ] && { cat "$work/report"; bad=1; }

# The lines a file lacks, and the holder of a part that has one, written or
# named. The fields are split at `|`, which no path or comment syntax
# holds, so that an empty one (a syntax that needs no close) stays a field.
awk -F'\t' '$1 == "missing" || $1 == "holder" { $1 = $1; print }' OFS='|' "$work/found" > "$work/fix"
if [ "$apply" -eq 0 ]; then
  awk -F'|' '
    $1 == "missing" { print $2 ": no SPDX line at its head" }
    $1 == "holder" { print $2 ": line " $3 " is not " $4 }' "$work/fix"
  [ -s "$work/fix" ] && bad=1
else
  # missing|file|line|open|close|identifier|holder: the two lines go in
  # at that line; holder|file|line|text: that line becomes the text.
  while IFS='|' read -r what file at first second id holder; do
    tmp=$file.lic-tmp
    if [ "$what" = missing ]; then
      awk -v at="$at" -v open="$first" -v shut="$second" -v id="$id" -v holder="$holder" '
        function line(text) { return open " " text (shut == "" ? "" : " " shut) }
        function header() { print line("SPDX-License-Identifier: " id); print line("Copyright (c) " holder) }
        NR == at { header() }
        { print }
        END { if (NR < at) header() }' "$file" > "$tmp"
    else
      awk -v at="$at" -v text="$first" 'NR == at { print text; next } { print }' "$file" > "$tmp"
    fi
    # Back through the file itself, so its mode (a script's executable
    # bit) survives the rewrite.
    cat "$tmp" > "$file"
    rm -f "$tmp"
  done < "$work/fix"
fi

# The text of every licence in use, by its identifier.
awk -F'\t' '$1 == "id" { print $2 }' "$work/found" | LC_ALL=C sort -u > "$work/ids"
while IFS= read -r id; do
  [ -s "LICENSES/$id.txt" ] || { echo "LICENSES/$id.txt: missing, and $id is in use"; bad=1; }
done < "$work/ids"

if [ "$bad" -eq 0 ]; then
  if [ "$apply" -eq 1 ]; then
    echo "licenses: SPDX lines written"
  else
    echo "licenses: every file in scope names its licence"
    echo "texts: $(tr '\n' ' ' < "$work/ids" | sed 's/ $//')"
  fi
fi
exit "$bad"
