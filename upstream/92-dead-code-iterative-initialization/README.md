<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][dataflow] Dead-code analysis initializes by recursion on nesting depth

On llvm main at 416f328b (the pin), `DeadCodeAnalysis::initialize` ends
in `initializeRecursively(top)`, which calls itself for every op nested
in every region of every op it visits
(`mlir/lib/Analysis/DataFlow/DeadCodeAnalysis.cpp`, *read*: one native
frame, with a `scope_exit` and the debug output's temporaries, per level
of region nesting). Every sparse forward analysis loads dead-code
analysis, so SCCP, the integer range analysis and the analyses of ours
on `DataFlowSolver` need a native stack that grows with the depth of the
IR. Under the compiler's one small, measured stack for every thread
(proposals/0000 D33, C43), a deeply nested function (a generated `else
if` chain is one match per branch, nested) reaches the guard: the tools'
stack limit is then a limit on the programs the compiler accepts.

## Reproduce

A function of `scf.execute_region` (or `scf.if`) nested N deep under
`-sccp` on a thread whose stack is small: the native depth is linear in
N (*read*; no depth that overflows is measured).

## Patch

`llvm.patch`, applying after the patches before it (05, 29 and 65 touch
the same file): the same ops visited in the same pre-order from an
explicit worklist, each entry carrying whether a symbol table encloses
it, which `visitCallOperation` reads; `hasSymbolTable` is restored to its
value at entry, as the recursion left it. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request, after an RFC on Discourse for the family of
  MLIR's recursions on input size (proposals/0000 C99: walks, the printer
  and parser, attributes, clone, destruction, region DCE, call graph
  construction, slices), each family its own pull request.
- Upstream test: a lit test whose input nests a region a few thousand
  deep, run under `-sccp` (or a unit test running the solver on a thread
  with a small stack).
- The patch goes when the pin initializes the analysis without recursion
  on nesting depth.
