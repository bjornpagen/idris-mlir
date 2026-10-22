# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# One row made wrong, so that `relation` (relations.awk) must name it: its
# input is the declared table, then the derived one; it writes both, one
# row changed, to `declaredOut` and `derivedOut`, and prints the start of
# the finding the change must bring, `<op> (<symbol>): <relation>:`.
#
# The row is a declaration made wrong where some op's function makes the
# relation bite (the first such op: its crash, exit, change or silence
# dropped or added), so that what is planted is a wrong declaration of a
# real function. Where no function of this runtime makes it bite, the
# first op's function is read wrong instead, so that every relation is
# shown to catch what it forbids on every target.

function has(w, word) { return index(" " w " ", " " word " ") > 0 }

function without(w, word,   out, n, parts, i) {
  n = split(w, parts, " ")
  out = ""
  for (i = 1; i <= n; i++)
    if (parts[i] != word && parts[i] != "nothing")
      out = out (out == "" ? "" : " ") parts[i]
  return out == "" ? "nothing" : out
}

function written(i,   m, positions, k) {
  if (dfact[i, 7] == "-")
    return 0
  m = split(dfact[i, 7], positions, ",")
  for (k = 1; k <= m; k++)
    if (positions[k] + 0 < operands[i])
      return 1
  return 0
}

function defined(i) { return (i in present) }

FNR == NR {
  if ($1 == "op") {
    ++count
    symbol[count] = $2
    mnemonic[count] = $3
    operands[count] = $4 + 0
    w = ""
    for (j = 5; j <= NF; j++)
      w = w (w == "" ? "" : " ") $j
    words[count] = w
    row[$2] = count
  } else {
    other[++others] = $0
  }
  next
}

$1 == "fn" && $3 != "missing" && ($2 in row) {
  for (j = 1; j <= NF; j++)
    fact[$2, j] = $j
  hasFact[$2] = 1
}
{ derived[++derivedCount] = $0 }

END {
  for (i = 1; i <= count; i++)
    if (symbol[i] in hasFact) {
      present[i] = 1
      for (j = 1; j <= 7; j++)
        dfact[i, j] = fact[symbol[i], j]
    }

  chosen = 0
  side = ""
  for (i = 1; i <= count && !chosen; i++) {
    if (!defined(i))
      continue
    w = words[i]
    ends = has(w, "crash") || has(w, "exit")
    if (relation == "stops" && dfact[i, 3] == "yes" && ends) {
      words[i] = without(without(w, "crash"), "exit")
      chosen = i
    } else if (relation == "crash" && dfact[i, 4] == "yes" && has(w, "crash")) {
      words[i] = without(w, "crash")
      chosen = i
    } else if (relation == "exit" && dfact[i, 5] == "yes" && has(w, "exit")) {
      words[i] = without(w, "exit")
      chosen = i
    } else if (relation == "inert" && (dfact[i, 6] == "none" || dfact[i, 6] == "reads") && w == "nothing") {
      words[i] = "memory"
      chosen = i
    } else if (relation == "operand" && written(i) && has(w, "operands")) {
      words[i] = without(w, "operands")
      chosen = i
    } else if (relation == "writes" && dfact[i, 6] == "writes" && w != "nothing") {
      words[i] = "nothing"
      chosen = i
    }
  }
  if (chosen)
    side = "declared"
  for (i = 1; i <= count && !chosen; i++) {
    if (!defined(i))
      continue
    w = words[i]
    if (relation == "stops" && !has(w, "crash") && !has(w, "exit")) {
      dfact[i, 3] = "yes"
      chosen = i
    } else if (relation == "crash" && !has(w, "crash")) {
      dfact[i, 4] = "yes"
      chosen = i
    } else if (relation == "exit" && !has(w, "exit")) {
      dfact[i, 5] = "yes"
      chosen = i
    } else if (relation == "inert" && has(w, "memory")) {
      dfact[i, 6] = "none"
      chosen = i
    } else if (relation == "operand" && operands[i] > 0 && !has(w, "operands")) {
      dfact[i, 7] = "0"
      chosen = i
    } else if (relation == "writes" && w == "nothing") {
      dfact[i, 6] = "writes"
      chosen = i
    }
  }
  if (!chosen)
    exit 1
  if (side == "")
    side = "derived"

  for (i = 1; i <= count; i++)
    print "op", symbol[i], mnemonic[i], operands[i], words[i] > declaredOut
  for (k = 1; k <= others; k++)
    print other[k] > declaredOut
  for (k = 1; k <= derivedCount; k++) {
    split(derived[k], f, " ")
    if (f[1] == "fn" && symbol[chosen] == f[2] && side == "derived")
      print "fn", f[2], dfact[chosen, 3], dfact[chosen, 4], dfact[chosen, 5], dfact[chosen, 6], dfact[chosen, 7] > derivedOut
    else
      print derived[k] > derivedOut
  }
  print mnemonic[chosen] " (" symbol[chosen] "): " relation ":"
}
