<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] SymbolTable::walkSymbolTables recurses once per level of nesting

On llvm main at 416f328b (the pin), and on main on 2026-10-21,
`SymbolTable::walkSymbolTables` (`mlir/lib/IR/SymbolTable.cpp:336`)
calls itself for every operation of every block of every region it
visits (`:352`), so its native depth is the nesting depth of the IR,
whatever symbols the IR holds (*read*). Three callers reach it: dead-code
analysis, which every sparse forward analysis loads, walks the symbol
tables when it initializes (`initializeSymbolCallables`,
`DeadCodeAnalysis.cpp:241`); the inliner's use lists
(`CGUseList`, `Inliner.cpp:152`); and `SymbolUserMap`
(`SymbolTable.cpp:1079`). Under the compiler's one small, measured stack
for every thread (proposals/0000 D33, C43, C99), a deeply nested
function (a generated `else if` chain is one match per branch, nested)
reaches the guard in each of them: the tools' stack limit would then be
a limit on the programs the compiler accepts.

What reaches it in this repository: the integer range solves (the ranges
analysis, idr-narrow's copies), each loading dead-code analysis; and
idr-inline, which runs upstream's inliner. The third caller is not reached: nothing in the tree, and no
upstream pass the pipeline runs, builds a `SymbolUserMap`.
`tests/upstream-dead-code-iterative-initialization` shows it: its
10,000-deep nest on a 256 KiB thread overflows here, after patch 92 has
made the rest of dead-code analysis's initialization iterative.

## Reproduce

`nested-tables.sh DEPTH` writes a module nesting `builtin.module` DEPTH
deep around a private function. `mlir-opt -inline nested.mlir
-emit-bytecode -o /dev/null` walks its symbol tables; under a small
stack (`ulimit -s 256`) a few thousand levels overflow it at the pin
(*conjecture* on the depth: no overflowing depth is measured). The
textual parser recurses on the same depth through each operation's
parse hook (PINS.md `mlir-recursion`), so through `mlir-opt` the walk is
seen alone only on IR read from bytecode; the patch's unit test builds
the nest in memory.

## Patch

`llvm.patch`, applying after 80, whose iterative walks it uses: the walk
is a stage-aware operation walk with a stack of what is known of each
operation whose walk has begun, whether it is a symbol table and whether
all uses of its nested symbols are visible. Each operation computes that
from its parent's before its regions are walked, as the recursion did,
and a symbol table is passed to the callback after all its regions, so
the callback sees the same tables in the same post-order with the same
visibility; the void stage walk advances to the next operation only
after walking the current one, as the recursion's loop did. The unit
test, `SymbolTable.WalkSymbolTablesDeepNestingOnASmallStack` in
`mlir/unittests/IR/SymbolTableTest.cpp`, walks a module holding a chain
nested 10,000 deep with a module innermost on a 256 KiB thread, and
checks the two tables' order and visibility. `tools/bootstrap.sh`
applies it with every `upstream/*/llvm.patch`, in name order. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request, `[mlir]`, after the RFC on Discourse for the
  family of MLIR's recursions on input size
  (upstream/10-recursive-attribute-parser's plan), and after 80's pull
  request, on whose iterative stage walk it relies: without it the walk
  still recurses inside `Visitors.cpp`.
- Upstream test: the unit test above, with `SymbolTableTest.cpp`'s
  `SymbolUserMap` test and the lit tests of SCCP, the inliner and
  dead-code analysis unchanged.
- The patch goes when the pin walks symbol tables without recursion on
  nesting depth.
