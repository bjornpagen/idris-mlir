# The cut-over hunt: what stays one way, and what was found to be one already

2026-10-01. After the representation refactor, the tree was read for old
mechanisms left beside new ones. What follows is what was found and what
was decided; the deletions are in the commits of the same day.

- **Pinned MLIR workarounds.** `make test-mlir-tools` passes, so every
  `tests/upstream` reproducer still reproduces at the pinned LLVM; the six
  MLIR pins stay until their check fails. `linarray-escape` is retired:
  it pinned how contrib's `newArray` signature was treated, and contrib is
  no longer compiled (`libs/mlir-linear` has the `!*` signature).
- **`idr.effects`** is a fact the compiler infers, not one Idris proved,
  and its absence means "may do anything", so the discardable attribute
  is sound. What was duplicated is the consumer side: `Facts/Moves` and
  the dialect's `RemoveUnusedCall` re-derived what MLIR's effect queries
  derive for every op that declares its effects, while `func.call`
  declared none. The call's effects now come through an external
  `MemoryEffectOpInterface` model (`lib/Facts/CallEffects.cc`), and the
  hand-rolled layer is gone.
- **Three worklists, one solver.** Borrow inference, effects inference and
  escape analysis are call-graph summaries; `DataFlowSolver` solves
  lattices over program points (exclusivity). Different problems, not two
  ways of one thing. They stay.
- **`Closed.idr` and idr-eval.** Closed reduces types and implementations,
  compile-time values only Idris's elaboration knows; it folds no
  primitive. idr-eval evaluates closed calls at the MLIR level. Both stay.
- **Two program shapes.** `main : Int` programs (the exit status is the
  value) were this compiler's own invention for the semantics tests, with
  their own flow in `tools/compile.sh`, `tests/lib/e2e.sh` and
  `Frontend/Main.idr`, and no Chez oracle. They became IO programs that
  print the value (`Prog.result`, with an `Oracle.idr` that proves it the
  expected stdout), the Int flow went, and Chez checks them too. Two things
  the one flow showed: a module Idris reloads from its TTC keeps no
  location inside a term, so a crash names the function, not the
  operation, and a profile rejection reports the definition's line; and
  Idris's own inliner drops a division whose quotient is unused, where this
  compiler keeps the crash as an effect in program order
  (`tests/e2e/v0/crash-div-zero`, marked `no-chez`). Whether an undemanded
  crash is an effect is a decision still to take.
