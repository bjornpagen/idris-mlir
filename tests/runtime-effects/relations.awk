# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Each op's declaration held to what its runtime function does: its input
# is the declared table (runtests --runtime-effects), then the derived one
# (derive.awk). Prints, in the declared table's order, one finding per
# relation an op breaks, `<op> (<symbol>): <relation>: <what>`, and
# nothing when every op keeps every relation:
#
#   missing   the function is in the runtime;
#   stops     a function that never returns is an op's that may crash or exit;
#   crash     one that reaches a crash's ending is an op's that may crash;
#   exit      one that reaches the exit's ending is an op's that may exit;
#   inert     one LLVM proves writes no memory is an op's that changes none,
#             and neither crashes nor exits, each of which writes its message;
#   operand   one that writes through an operand it never lets go of is an
#             op's that changes an operand's memory;
#   writes    one LLVM proves writes memory is an op's that changes some.
#
# Where LLVM knows nothing of what a function does (memory `unknown`), the
# memory relations do not judge it; the endings, the calls and the
# parameters still do.

FNR == NR {
  if ($1 == "op")
    ops[++count] = $0
  next
}

$1 == "fn" { fact[$2] = $0 }

function says(word) { return index(said, " " word " ") > 0 }

function finding(relation, what) { print mnemonic " (" symbol "): " relation ": " what }

END {
  for (i = 1; i <= count; i++) {
    n = split(ops[i], d, " ")
    symbol = d[2]
    mnemonic = d[3]
    operands = d[4] + 0
    said = " "
    words = ""
    for (j = 5; j <= n; j++) {
      said = said d[j] " "
      words = words " " d[j]
    }
    if (!(symbol in fact)) {
      finding("missing", "its function is not in the runtime")
      continue
    }
    split(fact[symbol], f, " ")
    if (f[3] == "missing") {
      finding("missing", "its function is not in the runtime")
      continue
    }
    noreturn = f[3]
    crashes = f[4]
    exits = f[5]
    memory = f[6]
    written = f[7]
    ends = says("crash") || says("exit")
    if (noreturn == "yes" && !ends)
      finding("stops", "its function never returns, and it declares neither a crash nor an exit")
    if (crashes == "yes" && !says("crash"))
      finding("crash", "its function may crash, and it declares no crash")
    if (exits == "yes" && !says("exit"))
      finding("exit", "its function may end the run normally, and it declares no exit")
    if ((memory == "none" || memory == "reads") && (says("memory") || ends))
      finding("inert", "its function writes no memory, and it declares" words)
    if (written != "-") {
      m = split(written, positions, ",")
      for (k = 1; k <= m; k++)
        if (positions[k] + 0 < operands && !says("operands"))
          finding("operand", "its function writes through operand " positions[k] ", and it declares no change to an operand's memory")
    }
    if (memory == "writes" && !says("memory") && !says("operands") && !ends)
      finding("writes", "its function writes memory, and it declares no change to any")
  }
}
