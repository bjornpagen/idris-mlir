# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The repository's rules (the `check` suite), each shown to catch what it
# forbids and to pass what it allows, on files planted beside it.
#
# A rule's check is a shell function of a tree's root, CHECK ROOT, that
# prints its findings in the tree at ROOT, one per line, each starting with
# the path of the file it is in, from ROOT, and a colon (`path:line: what`
# or `path: what`), and nothing when the tree keeps the rule. The test
# runs it on the repository ($root) and, through `planted`, on its own
# two planted trees, each laid out as the repository is (the same paths
# from its root, so the check walks it unchanged):
#
#     witness/    files that break the rule, one per way of breaking it
#                 the rule names: each must be found
#     near-miss/  files as close to breaking it as the rule allows (the
#                 allowed spelling, the exception, the word in a comment):
#                 none may be found
#
# So a rule that finds nothing fails on its witness, and one that finds
# too much on its near miss. A check that walks the whole repository
# leaves out every test's witness/ and near-miss/, and a planted file
# carries the licence line its kind needs (tools/licenses.sh), as every
# file of the tree does.

# planted CHECK: CHECK run on the test's witness/ and near-miss/ (above),
# one line for each: every file of witness/ is named by a finding, and
# near-miss/ has none. A tree missing is said, and fails.
planted() {
  for pl_tree in witness near-miss; do
    if [ ! -d "$here/$pl_tree" ]; then
      say "planted: no $pl_tree/ beside the check"
      return
    fi
  done
  "$1" "$here/witness" > "$work/planted.witness" 2> "$work/planted.err"
  (cd "$here/witness" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) > "$work/planted.files"
  awk -v findings="$work/planted.witness" '
    BEGIN { while ((getline line < findings) > 0) { sub(/^[ \t]+/, "", line); found[++n] = line } }
    { for (i = 1; i <= n; i++) if (index(found[i], $0 ":") == 1) next; print "  " $0 }' \
    "$work/planted.files" > "$work/planted.missed"
  if [ ! -s "$work/planted.files" ]; then
    say "witness: nothing planted"
  elif [ -s "$work/planted.missed" ]; then
    say "witness: planted files the check does not find:"
    cat "$work/planted.missed"
    show "$work/planted.err"
  else
    say "witness: each planted file is found"
  fi
  "$1" "$here/near-miss" > "$work/planted.near-miss" 2> "$work/planted.err"
  if [ -z "$(cd "$here/near-miss" && find . -type f)" ]; then
    say "near miss: nothing planted"
  elif [ -s "$work/planted.near-miss" ]; then
    say "near miss: found, though it keeps the rule:"
    show "$work/planted.near-miss"
  else
    say "near miss: nothing found"
  fi
}
