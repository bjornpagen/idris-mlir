# [mlir] Forward data-flow analyses resolve each callee by scanning the module

At `llvmorg-23.1.2`, the sparse and dense forward data-flow analyses look
up the callee of every call they visit by a linear scan of the nearest
symbol table, so an interprocedural forward analysis over a module of n
functions that call each other takes time quadratic in n. `sccp`,
`int-range-optimizations` and `remove-dead-values` all show it; the
backward analyses in the same files do not, because they resolve callees
through a `SymbolTableCollection`.

## Reproduce

`calls.sh N > calls.mlir` writes a module of N functions, each calling the
next:

```mlir
module {
  func.func @f0(%x: i32) -> i32 {
    %r = func.call @f1(%x) : (i32) -> i32
    return %r : i32
  }
  func.func private @f1(%x: i32) -> i32 {
    ...
  func.func private @f15999(%x: i32) -> i32 {
    %c = arith.constant 7 : i32
    return %c : i32
  }
}
```

```
$ for n in 2000 4000 8000 16000; do
    sh calls.sh $n > c$n.mlir
    time mlir-opt c$n.mlir --sccp -o /dev/null
  done
```

| functions | `--sccp` | `--int-range-optimizations` | `--remove-dead-values` | parse alone |
| --- | --- | --- | --- | --- |
| 2,000 | 0.08 s | | | 0.02 s |
| 4,000 | 0.21 s | 0.40 s | 0.24 s | 0.04 s |
| 8,000 | 0.72 s | | | 0.07 s |
| 16,000 | 2.54 s | 5.07 s | 2.79 s | 0.12 s |

Each doubling of the module takes three to four times as long. Expected:
linear time, as parsing it takes.

## Cause

`AbstractSparseForwardDataFlowAnalysis::visitCallOperation`
(`mlir/lib/Analysis/DataFlow/SparseAnalysis.cpp:237`) and
`AbstractDenseForwardDataFlowAnalysis::visitCallOperation`
(`mlir/lib/Analysis/DataFlow/DenseAnalysis.cpp:104`) decide whether the
callee is external with `call.resolveCallable()`, which resolves the
symbol with `SymbolTable::lookupNearestSymbolFrom`: a scan of the symbol
table's ops, comparing names. The analysis visits every call at least
once, so a module of n functions with a call each costs n scans of n ops.

The backward analyses of the same files resolve with
`call.resolveCallableInTable(&symbolTable)` (`SparseAnalysis.cpp:509`,
`DenseAnalysis.cpp:437`), a `SymbolTableCollection` their constructor
takes, and `DeadCodeAnalysis`, which every sparse forward analysis runs
with, owns one (`DeadCodeAnalysis.h:248`) for the same lookups.

## Proposed fix

Give the forward analyses a `SymbolTableCollection` and resolve with
`resolveCallableInTable`, as the backward ones do. Taking it in the
constructor, as the backward analyses do, would change every forward
analysis's constructor; owning one, as `DeadCodeAnalysis` does, changes
none. A table is built on the first lookup and the IR does not change
while the solver runs.

## Our workaround

None. idris-mlir's simplification runs these analyses on whole programs,
every round, and the scans were 8 to 9 percent of a compile of
`k-nucleotide` or `every-types-export`.

## Patch

`llvm.patch` is the proposed fix: `AbstractSparseForwardDataFlowAnalysis`
and `AbstractDenseForwardDataFlowAnalysis` each own a
`SymbolTableCollection` and resolve callees through it. It is not a
backport: llvm's main (checked at 155462f440f, October 2026) still calls
`resolveCallable()` in both places, and no issue or pull request covers
it. It changes no result, only the time, so its test upstream is the
existing data-flow tests; the scaling is the reproducer's, quoted in the
pull request.

## Upstreaming plan

- Where: a pull request to llvm/llvm-project (MLIR data-flow analysis),
  marked NFC, with this report's table before and after.
- Upstream test: none of its own, being NFC; `mlir/test/Analysis/DataFlow`
  and the `sccp`, `int-range-optimizations` and `remove-dead-values` tests
  cover the lookups it changes.
- Status: not sent.
