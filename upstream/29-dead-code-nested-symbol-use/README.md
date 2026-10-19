<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][dataflow] A non-call symbol use in a nested symbol table is never found, so remove-dead-values poisons the function it names

On llvm main at 7208ba24 (the pin), and still on main on 2026-10-19,
`DeadCodeAnalysis::initializeSymbolCallables`
(`mlir/lib/Analysis/DataFlow/DeadCodeAnalysis.cpp:225-238`) walks every
symbol table under the analysis' top and marks a callable with a non-call
use as having unknown predecessors. It resolves the use with
`symbolTable.lookupSymbolIn(top, use.getSymbolRef())`. The flat reference
names a symbol of the table being walked (`symTable`), which may be nested
below `top`; there the lookup finds nothing and the use is skipped
(`if (!symbol) continue;`). The callable's predecessors then count as all
known, none of them a call, and liveness finds its return values dead.

## Reproduce

`nested-symbol-use.mlir`, with the toolchain's mlir-opt:
`--remove-dead-values` turns `@inc`'s body into `%0 = ub.poison : i64;
return %0`. `@inc` is reached only through `func.constant` and
`func.call_indirect`, inside `builtin.module @inner`. The same module at the
top level keeps `@inc`. In the compiler this was a silent miscompile: every
idr program is an `idr.program`, a symbol table nested in the module, and a
label reached only through an `idr.closure` returned poison after
remove-dead-values (tests/canon-upstream-passes printed 255 for 510).

## Expected

A non-call use of a symbol of any walked table marks that symbol's
callable as having unknown predecessors.

## The fix

`llvm.patch`: inside the walk of one table, `top` names that table, so
the use is resolved in the table it names a symbol of, and the fallback
for uses that cannot be gathered marks that table's callables, all a use
in it can name. Written so as to touch no line
upstream/05-forward-dataflow-callee-lookup rewrites; upstream, the change
is to resolve the use in `symTable` and to walk `symTable` in the
fallback.

## Patch

`llvm.patch`, applied by tools/bootstrap.sh; checked by
tests/upstream-dead-code-nested-symbol-use (the return value is kept).

## Upstreaming plan

An issue and a PR to llvm/llvm-project, `[mlir][dataflow]`, with this
reproducer as a test in `mlir/test/Transforms/remove-dead-values.mlir` (a
nested module whose private function is reached through `func.constant`).
Status: not filed; carried; check-mlir not run.
