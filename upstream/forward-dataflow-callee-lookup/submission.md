Approach changed: the old patch gave each forward analysis its own SymbolTableCollection, beside DeadCodeAnalysis's; now the solver holds one collection per run, shared by every analysis it runs, and DeadCodeAnalysis's member is gone.

# Submission

Status: file a pull request only, marked NFC.

One pull request on llvm/llvm-project, one commit, the diff in
`llvm.patch`. No Bugzilla bug, no issue. Author: Bjorn, as an individual,
outside any employer.

The pull request title is the first line below; the body is the rest.
Squash-and-merge uses both as the commit message.

## Pull request

```
[mlir][dataflow][NFC] Resolve callees from one symbol table per run

AbstractSparseForwardDataFlowAnalysis::visitCallOperation and
AbstractDenseForwardDataFlowAnalysis::visitCallOperation ask,
on every visit of a call, whether the callee is an external
declaration, using CallOpInterface::resolveCallable(). Without a
SymbolTableCollection that is SymbolTable::lookupNearestSymbolFrom,
a walk over the operations of the enclosing symbol table. A call is
visited again whenever its operands or its callee's returns change,
so an interprocedural forward analysis over a module of n functions
that call each other does O(n^2) work. DeadCodeAnalysis, which every
forward analysis runs with, already resolves the same callees through
a SymbolTableCollection of its own.

The solver now holds one SymbolTableCollection for the
duration of initializeAndRun, and analyses reach it through
DataFlowAnalysis::getSymbolTables(). The forward analyses resolve their
callees through it, and DeadCodeAnalysis uses it instead of its member.
The IR does not change during a run, so each lookup finds the same
symbol as before; the tables are built on first use and none outlives
the run that built it. The backward analyses keep resolving through
the collection their constructors take: moving them onto the solver's
changes their public constructors and is left to a separate change.

No test: results are unchanged and the existing sccp,
int-range-optimizations and remove-dead-values tests cover these
lookups. On a module of 16,000 functions, each calling the next,
--sccp goes from 9.6 s to 0.7 s and --int-range-optimizations from
17.5 s to 1.9 s.
```
