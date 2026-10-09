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

Best of three, on a loaded 4-core x86_64 machine, with an mlir-opt
whose data-flow sources and three passes are built at `-O2` from the
llvmorg-23.1.2 sources, the pin then, with and without `llvm.patch` and
linked against its Release libraries:

| functions | pass | llvmorg-23.1.2 | with `llvm.patch` |
| --- | --- | --- | --- |
| 4,000 | `--sccp` | 0.60 s | 0.25 s |
| 4,000 | `--int-range-optimizations` | 1.22 s | 0.33 s |
| 4,000 | `--remove-dead-values` | 0.71 s | 0.36 s |
| 16,000 | `--sccp` | 8.80 s | 0.67 s |
| 16,000 | `--int-range-optimizations` | 17.32 s | 1.02 s |
| 16,000 | `--remove-dead-values` | 9.75 s | 1.29 s |

Parsing the 16,000-function module alone takes about 0.3 s. Four times
the functions take 8 to 14 times as long unpatched, and 2.7 to 3.6
times patched.

## Cause

`AbstractSparseForwardDataFlowAnalysis::visitCallOperation`
(`mlir/lib/Analysis/DataFlow/SparseAnalysis.cpp:237`) and
`AbstractDenseForwardDataFlowAnalysis::visitCallOperation`
(`mlir/lib/Analysis/DataFlow/DenseAnalysis.cpp:104`; the same lines on
`main`) decide whether the callee is an external declaration with
`call.resolveCallable()`, before they read the call's predecessors. With no `SymbolTableCollection` that is
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

The solver builds one `SymbolTableCollection` for each
`initializeAndRun`, and `DataFlowAnalysis::getSymbolTables()` hands it
to any analysis. The forward analyses resolve callees with
`resolveCallableInTable(&getSymbolTables())`, and `DeadCodeAnalysis`
drops its member and uses the same collection, so one set of tables
serves the run and none outlives it. No constructor changes.

The solver holds the collection through a pointer to a local of
`initializeAndRun`, null outside a run, and `getSymbolTables()`
asserts it is set. That is the lifetime of the fact it caches: symbol
tables are valid only while the IR is frozen, and the solver only
guarantees that during a run; outside one there is nothing a cache
could hold that a later run may trust. An owned member reset per run
would make the tables reachable between runs, where they are either
stale or rebuilt with nobody bounding their lifetime, and resetting
one needs API that `SymbolTableCollection` does not have (no `clear()`,
and its user-declared virtual destructor leaves it without move
assignment). The only code that runs during a run is an analysis's
`initialize` and `visit`, which is where `getSymbolTables()` is called.
Analyses that call `resolveCallable()` themselves, in or out of tree,
see no change.

Moving `DeadCodeAnalysis` onto the run's tables also changes one
behaviour: its member lived as long as the solver, so a second
`initializeAndRun` after the IR changed, which the solver's
documentation describes, looked symbols up in tables built before the
change. No in-tree pass re-runs a solver that way. The pull request
says so, and is therefore not tagged NFC.

The backward analyses keep their `SymbolTableCollection &` constructor
parameter: removing it changes public constructors of two base classes
and their subclasses in and out of tree, so it is a follow-up.

Upstream `main` at `7208ba24` (8 October 2026) still calls
`resolveCallable()` at the same two lines and keeps
`DeadCodeAnalysis`'s own collection; `llvm.patch` applies to it
unchanged. No issue or pull request covers it. #155088 (merged) made
lookups stay inside the analysis root, for a race between function
passes; this change keeps that and builds a collection per run, so no
tables are shared between threads. The open #193112 edits
`DataFlowFramework.h` near the same lines and may need a rebase of
whichever lands second.

## Our workaround

None. idris-mlir's simplification runs these analyses on whole programs,
every round, and the scans were 8 to 9 percent of a compile of
`k-nucleotide` or `every-types-export`.

## Patch

`llvm.patch` is the pull request as one commit, generated against `main`
at `7208ba24`, the pin; it applied unchanged to llvmorg-23.1.2 too, so
there never was a separate trunk diff. `DataFlowSolver` points at the
run's `SymbolTableCollection` while `initializeAndRun` runs,
`DataFlowAnalysis::getSymbolTables()` returns it, and the forward analyses
and `DeadCodeAnalysis` resolve through it. It adds a pointer to
`DataFlowSolver` and removes a member from `DeadCodeAnalysis`, so
everything that includes `DataFlowFramework.h` rebuilds.

Checked against llvmorg-23.1.2, the pin then: an mlir-opt linked with
the patched data-flow
sources and the three passes gives byte-for-byte the same output and
exit status as the unpatched one on every RUN line of the `sccp`,
`int-range-optimizations` and `remove-dead-values` tests in
`mlir/test` (24 runs; the ones that use the test dialect fail to parse
in both, since that build has no test dialect), on `calls.sh 16000`,
and on a module with declarations, address-taken functions and a
nested module. The dense forward analysis has no in-tree pass outside
the test passes, so its one-line change is checked only by compiling.
Against `main`, the four changed sources compile with `main`'s headers
(the interface `.inc` files regenerated from `main`'s `.td` where they
differ). On `main` itself, see Testing on main.

## Testing on main

On llvm main at 7208ba24 (2026-10-08), with the seven code diffs of
01-08 applied together (02-07's `llvm.patch` and 08's
`pull-request.diff`), a Release build with assertions
(`-DLLVM_ENABLE_PROJECTS=mlir -DLLVM_TARGETS_TO_BUILD=Native
-DBUILD_SHARED_LIBS=ON -DLLVM_ENABLE_ASSERTIONS=ON`, clang 18, x86_64
Linux) builds without errors and passes `ninja check-mlir`: 4102 passed,
630 unsupported, 1 expectedly failed, none failed.

This patch adds no test: in-tree results do not change, and the
`sccp`, `int-range-optimizations`, `remove-dead-values` and
`Analysis/DataFlow` tests that exercise the lookups it moves pass in the
run above. The dense forward analysis is exercised there only through
its test passes.

## Upstreaming plan

Status: file a pull request only.

- Where: one commit on a pull request to llvm/llvm-project (MLIR data-flow
  analysis), tagged `[mlir][dataflow]`. The title and the squash
  commit message are in `submission.md`. No issue: a slowdown, not a
  crash or a miscompile.
- Upstream test: none new, since in-tree results do not change; the
  existing `sccp`, `int-range-optimizations`, `remove-dead-values` and
  `mlir/test/Analysis/DataFlow` tests cover the lookups it moves, and the
  pull request quotes the 16,000-function timing.
- Follow-up: move the backward analyses onto `getSymbolTables()` and drop
  their `SymbolTableCollection &` constructor parameter, as its own pull
  request.
- Drop: when the pin moves past the upstream commit, delete `llvm.patch`,
  its `PINS.md` entry and `tests/upstream/forward-dataflow-callee-lookup`.
