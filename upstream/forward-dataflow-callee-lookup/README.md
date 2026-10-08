# [mlir] Forward data-flow analyses resolve each callee by scanning the module

At `llvmorg-23.1.2`, the sparse and dense forward data-flow analyses look
up the callee of every call they visit by a linear scan of the nearest
symbol table, so an interprocedural forward analysis over a module of n
functions that call each other takes time quadratic in n. `sccp`,
`int-range-optimizations` and `remove-dead-values` all show it.

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
$ for n in 4000 16000; do
    sh calls.sh $n > c$n.mlir
    time mlir-opt c$n.mlir --sccp -o /dev/null
  done
```

Best of three, an `-O2` mlir-opt built from the pinned sources with and
without `llvm.patch`, on a loaded 4-core machine:

| functions | pass | llvmorg-23.1.2 | with `llvm.patch` |
| --- | --- | --- | --- |
| 4,000 | `--sccp` | 0.53 s | 0.19 s |
| 4,000 | `--int-range-optimizations` | 0.89 s | 0.22 s |
| 4,000 | `--remove-dead-values` | 0.57 s | 0.18 s |
| 16,000 | `--sccp` | 9.56 s | 0.74 s |
| 16,000 | `--int-range-optimizations` | 17.47 s | 1.88 s |
| 16,000 | `--remove-dead-values` | 9.19 s | 1.04 s |

Parsing alone takes 0.08 s and 0.29 s. Four times the functions take 18
to 20 times as long unpatched, and about 4 times patched.

## Cause

`AbstractSparseForwardDataFlowAnalysis::visitCallOperation`
(`mlir/lib/Analysis/DataFlow/SparseAnalysis.cpp:237`) and
`AbstractDenseForwardDataFlowAnalysis::visitCallOperation`
(`mlir/lib/Analysis/DataFlow/DenseAnalysis.cpp:104`) decide whether the
callee is an external declaration with `call.resolveCallable()`, before
they read the call's predecessors. With no `SymbolTableCollection` that is
`SymbolTable::lookupNearestSymbolFrom`, a scan of the symbol table's ops
comparing names. A call is visited again each time its operand lattices
or its callee's return lattices change, so a module of n functions with a
call each costs some multiple of n scans of n ops.

The other lookup paths of the same run already use a table, each its own:
`DeadCodeAnalysis`, which every forward analysis runs with, owns a
`SymbolTableCollection` (`DeadCodeAnalysis.h:248`) that outlives the run,
and the backward analyses (`SparseAnalysis.cpp:509`,
`DenseAnalysis.cpp:437`) resolve through one their constructors take,
which their callers build for the one run. The fact all of them need,
"the symbol tables of this IR while it is frozen", belongs to the solver:
it is shared by every analysis it runs, and its lifetime is
`initializeAndRun`, the span over which the IR does not change.

## Proposed fix

The solver holds one `SymbolTableCollection` for the duration of
`initializeAndRun`; `DataFlowAnalysis::getSymbolTables()` hands it to any
analysis. The forward analyses resolve callees with
`resolveCallableInTable(&getSymbolTables())`, and `DeadCodeAnalysis` drops
its member and uses the same collection, so one set of tables serves the
run and none outlives it. No constructor changes. The backward analyses
keep their constructor parameter: removing it changes a public
constructor of two base classes and their subclasses in and out of tree,
so it is a follow-up, not part of an NFC change.

Upstream `main` (checked at `783e429bf40`, 8 October 2026) still calls
`resolveCallable()` in both forward analyses and keeps `DeadCodeAnalysis`'s
own collection; the patch applies to it unchanged. No open issue or pull
request covers it.

## Our workaround

None. idris-mlir's simplification runs these analyses on whole programs,
every round, and the scans were 8 to 9 percent of a compile of
`k-nucleotide` or `every-types-export`.

## Patch

`llvm.patch` is the proposed fix as one commit: `DataFlowSolver` owns the
run's `SymbolTableCollection` through a pointer that `initializeAndRun`
sets to a local and clears on exit, `DataFlowAnalysis::getSymbolTables()`
returns it, and the forward analyses and `DeadCodeAnalysis` resolve
through it. It changes `DataFlowSolver`'s layout, so everything that
includes `DataFlowFramework.h` rebuilds; it changes no result.

Checked against the pin: the patch applies; an `-O2` mlir-opt linked
with the patched data-flow sources and the three passes gives byte-for-byte
the same output and exit status as the unpatched one on every RUN line of
the `sccp`, `int-range-optimizations` and `remove-dead-values` tests in
`mlir/test` (24 runs; the ones that use the test dialect fail to parse in
both, since that build has no test dialect), on `calls.sh 16000`, and on a
module with declarations, address-taken functions and a nested module. The
dense forward analysis has no in-tree pass outside the test passes, so its
one-line change is checked only by compiling. `make test-idr` was not run
against a toolchain bootstrapped with this patch.

## Upstreaming plan

Status: file a pull request only, marked NFC.

- Where: one commit on a pull request to llvm/llvm-project (MLIR data-flow
  analysis), tagged `[mlir][dataflow][NFC]`. The title and the squash
  commit message are in `submission.md`. No Bugzilla report, and no new
  issue.
- Upstream test: none new, as for any NFC change; the existing `sccp`,
  `int-range-optimizations`, `remove-dead-values` and
  `mlir/test/Analysis/DataFlow` tests cover the lookups it moves, and the
  pull request quotes the 16,000-function timing.
- Follow-up: move the backward analyses onto `getSymbolTables()` and drop
  their `SymbolTableCollection &` constructor parameter, as its own pull
  request.
- Drop: when the pin moves past the upstream commit, delete `llvm.patch`,
  its `PINS.md` entry and `tests/upstream/forward-dataflow-callee-lookup`.
