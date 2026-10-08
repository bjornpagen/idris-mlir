# Submission

Status: file a pull request only, marked NFC.

File one pull request on llvm/llvm-project. One commit. Tag `[mlir]`.
Do not file a Bugzilla bug. Do not open an issue.

Author: Bjorn, an individual, outside any employer. The squash commit
message has no Assisted-by trailer and no GitHub mention.

The diff is `llvm.patch`. The pull request title is the first line below.
The pull request body is the rest of the same message, and a squash uses
that message as the commit.

## Squash commit message

```
[mlir][NFC] Symbol table for forward data-flow callees: lookupNearestSymbolFrom scans the module (k-nucleotide, 8 to 9 percent)

AbstractSparseForwardDataFlowAnalysis::visitCallOperation and
AbstractDenseForwardDataFlowAnalysis::visitCallOperation ask whether a
callee is external with CallOpInterface::resolveCallable(). That resolves
the symbol through SymbolTable::lookupNearestSymbolFrom, which walks the
operations of the nearest symbol table and compares names. A forward
analysis visits every call at least once, so a module of n functions that
call each other performs n scans of n operations. sccp,
int-range-optimizations and remove-dead-values all take that path. On a
chain of calls, --sccp takes 0.08 s, 0.21 s, 0.72 s and 2.54 s at 2,000,
4,000, 8,000 and 16,000 functions: each doubling of the module takes three
to four times as long, while parsing the same module stays near 0.02 s to
0.12 s.

The backward analyses in the same files already resolve callees with
CallOpInterface::resolveCallableInTable and a SymbolTableCollection.
DeadCodeAnalysis, which every sparse forward analysis runs with, owns one
for the same lookups. A SymbolTableCollection replaces the module scan
because it answers the same symbol lookup from tables built on first use,
so each later callee is a constant-time query. Each forward analysis now
owns a SymbolTableCollection, as DeadCodeAnalysis does, and resolves with
resolveCallableInTable. Owning the collection leaves the constructors of
every derived analysis as they are. The IR does not change while the
solver runs, so the cached tables stay valid, and a lookup resolves the
same symbol as before.

Before, those scans were 8 to 9 percent of a compile of k-nucleotide.
After, each callee is resolved from the symbol table, and that share of
the compile is no longer spent walking the module. Results are unchanged.
NFC apart from the time.

No dedicated new test file. The existing data-flow tests cover the
lookups: mlir/test/Analysis/DataFlow, and the sccp,
int-range-optimizations and remove-dead-values tests.

Bjorn, an individual, outside any employer.
```
