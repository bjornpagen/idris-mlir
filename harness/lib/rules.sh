# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The rules a refusal names, read from the one list of them the tests
# have: IdrRules.txt, which idris-mlir-tblgen -gen-rule-list writes from the
# dialect's ODS into the build, beside the dialect's other generated
# headers, so no test holds a rule's phrase or its category by hand. Where
# stage 2 is not built (make check), the typecheck build's list is read:
# the records are the same, so is the list. Each line of the list is the
# phrase a refusal renders, `unsupported (<phrase>)` for a rule of the
# first two categories, a tab, and the phrase of the rule's category:
# `megamorphic`, a construct whose choices no compile-time analysis
# bounds; `outside the language`, what the language this compiler
# implements does not have; or `user error`, a program Idris itself
# rejects, whose refusal carries Idris's own message. A line starting with
# `#` explains.

rules_list=$dev_prefix/foreign/idr/include/idr/IR/IdrRules.txt
[ -f "$rules_list" ] || rules_list=$typecheck_prefix/foreign/idr/include/idr/IR/IdrRules.txt

# rules_lines: the list's lines, phrase and category, without its comments;
# nothing, and status 1, when the list is missing.
rules_lines() {
  [ -f "$rules_list" ] || return 1
  grep -v '^#' "$rules_list" | grep .
}

# rule_phrases [CATEGORY]: the phrase of every rule, or of every rule of
# CATEGORY, one per line.
rule_phrases() {
  rules_lines | awk -F'\t' -v want="${1-}" 'want == "" || $2 == want { print $1 }'
}

# rule_category PHRASE: the category of the rule whose phrase is PHRASE;
# nothing, and status 1, when no rule has that phrase.
rule_category() {
  rule_category_found=$(rules_lines | awk -F'\t' -v phrase="$1" '$1 == phrase { print $2; exit }')
  [ -n "$rule_category_found" ] || return 1
  printf '%s\n' "$rule_category_found"
}
