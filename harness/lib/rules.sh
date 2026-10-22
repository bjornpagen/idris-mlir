# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The rules a refusal names, read from the one source of them, the
# dialect's specification, through the runner (`runtests --rules`,
# Facts.idr), so no test holds a rule's phrase or its category by hand.
# Each line is the phrase a refusal renders, `unsupported (<phrase>)` for a
# rule of the compiler's categories, a tab, and the phrase of the rule's
# category: a construct whose choices no compile-time analysis bounds,
# what the language this compiler implements does not have, or a program
# Idris itself rejects, whose refusal carries Idris's own message.

# rules_lines: every rule's line, phrase and category; nothing, and status
# 1, when the runner cannot give them.
rules_lines() {
  "$runtests" --rules
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
