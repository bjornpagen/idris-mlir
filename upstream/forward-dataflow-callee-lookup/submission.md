Approach changed: the old patch gave each forward analysis its own SymbolTableCollection, beside DeadCodeAnalysis's; now the solver holds one collection per run, shared by every analysis it runs, and DeadCodeAnalysis's member is gone.

# Submission

Status: file a pull request only.

One pull request on llvm/llvm-project, one commit, the diff in
`llvm.patch` (it applies unchanged to `main` at `7208ba24` and to
`llvmorg-23.1.2`). No issue: this is a slowdown, not a crash or a
miscompile. Author: Bjorn, as an individual, outside any employer.

The pull request title is the first line below; the body is the rest.
Squash-and-merge uses both as the commit message.

## Pull request

```
[mlir][dataflow] Resolve callees through one symbol table per run

AbstractSparseForwardDataFlowAnalysis and
AbstractDenseForwardDataFlowAnalysis check, on every visit of a call,
whether the callee is an external declaration, with
CallOpInterface::resolveCallable(). Without a SymbolTableCollection
that is SymbolTable::lookupNearestSymbolFrom, a walk over the
operations of the enclosing symbol table. A call is visited again
whenever its operands or its callee's return values change, so an
interprocedural forward analysis over a module of n functions that
call one another does O(n^2) work. DeadCodeAnalysis, which every
forward analysis runs with, already resolves the same callees through
a SymbolTableCollection of its own.

Symbol tables stay valid while the IR does not change, which the
solver guarantees for the duration of initializeAndRun. The solver now
builds one SymbolTableCollection per run, and analyses reach it
through a new protected DataFlowAnalysis::getSymbolTables(), which
asserts that the solver is running. The forward analyses resolve
callees through it, and DeadCodeAnalysis uses it in place of its
member. As before, the forward analyses look callees up only when the
analysis root is a symbol table, and each run has its own collection,
so no tables are shared between threads.

DeadCodeAnalysis's collection used to live as long as the solver, so
a second initializeAndRun after the IR changed, as the DataFlowSolver
documentation describes, looked symbols up in tables built before the
change. It now gets fresh tables. No in-tree pass re-runs a solver
that way, and in-tree results are unchanged. The backward analyses
keep the SymbolTableCollection their constructors take; moving them
to the solver's changes public constructors and is left for a
separate change.

No new test: the sccp, int-range-optimizations, remove-dead-values
and Analysis/DataFlow tests cover these lookups. On a module of
16,000 functions, each calling the next, --sccp goes from 8.8 s to
0.7 s and --int-range-optimizations from 17.3 s to 1.0 s (best of
three; the same change on llvmorg-23.1.2, built with -O2, x86_64).
```
