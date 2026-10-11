# `idr-simplify` on `front.mlir` does not finish in minutes

`idris-mlir-opt --idr-simplify` on `build/self/keep/front.mlir` was SIGKILL'd at 240s. stderr was empty. `-mlir-timing` prints only when `compile()` returns, so the kill produced no pass timing and no round remark.

The fixed point is finite. `Simplify::runOnOperation` in `foreign/idr/lib/Simplify/Pass.cc` runs MLIR's `CompositeFixedPointPass::runOnOperation` (`mlir/lib/Transforms/CompositePass.cpp`) over one round from `simplifyRound()` in `foreign/idr/lib/Simplify/Round.cppm`. The loop stops when a round leaves the module's `OperationFingerPrint` unchanged. Each member of a round is finite: `markLoopBreakers` puts `no_inline` on every cycle the inliner would otherwise unroll again next round, and specialization makes finitely many clones. `max-rounds` defaults to 64 (`IdrSimplify` in `foreign/idr/include/idr/Passes.td`). The composite pass runs one pipeline past that budget (`currentIter++ >= maxIter` fires before the fingerprint compare) and, with `ConvergenceFailureAction::Silent`, returns. `Simplify::exhausted` (`rounds.closed > limit`) then emits `unsupported (compile-time budget)`. A four-minute kill never reaches that check. The 64s sample below is still inside `mlir::parseSourceFile` and the opening walks of the first round.

What the sample shows, once simplify has started, is whole-module walks. Of the simplify samples, `OperationVerifier::verifyOpAndDominance` is on the stack about 53%, `markLoopBreakers` 20.5%, `idr::graph::components` 10.3%, `refersTo` 6.1%. `stronglyConnected` is absent. No simplify leaf is above about 1.4%. One compiler thread (`optMain`) does the work. The MLIR pool threads sit in `condition_variable::wait`.

The other agent's transcript (`8cdb3d9c-19e7-4616-84fb-72dda7f48067`) had not written a final answer when this note was written; it was still reading the verifier and the integer-range pass. The paragraphs above use the measured trace. The mechanism under each number is from the files named below, read for this note.

## The module

`build/self/keep/front.mlir` is the frontend emit of the compiler compiling itself. Measured: about 386 MiB, 1,357,310 lines, one module, 58,349 `func.func`, 7,619 `idr.data`. The text starts at `IdrisMLIR.Frontend.Driver.main` and ends at `$idris-mlir.root`.

Stage 0, the Chez frontend, already succeeded: 137 s, 9.1 GB. This note does not restate that run as a failure.

## When the loop stops

`Simplify::build` installs `createCompositeFixedPointPass` named `IdrSimplifyLoop`. The pipeline inside it is `OpenRound`, then `simplifyRound()`, then `CloseRound`. `OpenRound` records `steady_clock::now`. `CloseRound` increments `rounds.closed` and calls `idr::simplify::trace`.

`CompositeFixedPointPass::runOnOperation` keeps an `OperationFingerPrint` and repeats `runPipeline` on that pipeline. After a round it either stops for the budget or compares fingerprints. Equal fingerprints end the loop. `Simplify::runOnOperation` then emits the `fixpoint` remark when `rounds.closed` is within `max-rounds`. A copy of the pass builds its own loop (`Simplify(const Simplify &)`), because the pass manager copies an initialized pass before filling options.

`trace` in `foreign/idr/lib/Simplify/Trace.cppm` returns immediately when no remark is being read, before it counts functions or walks operations. An empty stderr therefore does not by itself say whether a round closed. The 240s kill does say `compile()` had not returned, because that is when `-mlir-timing` prints.

## What one round does

`simplifyRound()` is this pipeline, in order, each step a module pass:

1. `idr-loop-breakers` — `LoopBreakers::runOnOperation` calls `markLoopBreakers`.
2. `idr-effects` — `Effects::runOnOperation` infers `idr.effects` and records them.
3. `idr-identity` — `Identity::runOnOperation` calls `idr::identity::elide`.
4. `idr-inline` — builds a `CallGraph` and runs `Inliner::doInlining` for the calls the size rule allows, until an inliner iteration inlines nothing.
5. `idr-specialize` — `Specializer::run`.
6. `sccp`
7. `int-range-optimizations`
8. `idr-canonicalize` — `applyPatternsGreedily` on the module.
9. `cse`
10. `remove-dead-values{canonicalize=false}`
11. `symbol-dce`

Steps 6, 7, 9, and 10 run under `SymbolsHeld` (`Simplify::holdsSymbols`). That wrapper builds one `SymbolTable` and one `HoldMemo`, fingerprints the module, and `runPipeline`s the step. `idr-inline`, `idr-specialize`, and `symbol-dce` are not wrapped: they add or erase symbols. `idr-canonicalize` opens its own scope.

After each pass, `OpToOpPassAdaptor::runPipeline` in `mlir/lib/Pass/Pass.cpp` verifies the anchor operation when `verifyPasses` is on (the `PassManager` default) and the pass did not preserve every analysis:

```cpp
runVerifierNow = !pass->passState->preservedAnalyses.isAll();
if (runVerifierNow)
  passFailed = failed(verify(op, runVerifierRecursively));
```

`verify` is `OperationVerifier::verifyOpAndDominance` in `mlir/lib/IR/Verifier.cpp`: verify the operation, then build a `DominanceInfo` and walk contained regions. On this module that is every nested operation of all 58,349 functions.

Our steps call `markAllAnalysesPreserved` only when they rewrote nothing, which is what skips that walk:

- `LoopBreakers` when `markLoopBreakers` returns 0
- `Effects` when `idr::facts::record` wrote nothing
- `Identity` when `elided.calls == 0`
- the inliner when the fingerprint is unchanged
- `Specialize` when the fingerprint is unchanged
- `idr-canonicalize` when neither the greedy driver nor its listener rewrote
- `SymbolsHeld` when the inner step left the fingerprint unchanged
- `OpenRound` and `CloseRound` always

`sccp`, `int-range-optimizations`, `remove-dead-values`, and `symbol-dce` do not call `markAllAnalysesPreserved` (checked in `SCCP.cpp`, `IntRangeOptimizations.cpp`, `RemoveDeadValues.cpp`, `SymbolDCE.cpp`). `CSE::runOnOperation` calls it only when `changed` is false; a rewrite preserves only dominance analyses, which still verifies. `SymbolsHeld` skipping its own post-pass verify does not cancel the verify inside the inner `runPipeline`. A no-op `sccp` still verifies once. A first round on a fresh frontend module rewrites, so breakers, effects, identity, inline, specialize, sccp, integer range, canonicalize, dead values, and symbol-dce each add a full-module verify on top of the walk the pass itself does.

`markLoopBreakers` in `foreign/idr/lib/Simplify/Breakers.cppm` reads each body once. It builds `named` with one `idr::graph::refersTo` per function (`foreign/idr/lib/Graph/RefersTo.cppm`, `SymbolTable::getSymbolUses` on the body), builds the inlinable adjacency once from those lists, and on each breaker calls `drop`, which clears that vertex's edges in place and erases it from its predecessors. It does not call `idr::graph::stronglyConnected`. It calls `idr::graph::components` (`foreign/idr/lib/Graph/Scc.cppm`), which allocates a `Vertex` per inlinable function plus a root and runs `llvm::scc_begin`. The outer `again` loop repeats that until a pass marks nothing. Each pass that marks a breaker drops at least one live vertex, so the loop is finite; each pass is still a Tarjan walk of the whole inlinable graph.

Threading stays on one thread for the same reason the walks are module-sized. `OpToOpPassAdaptor::runOnOperation` uses `runOnOperationAsyncImpl` when the context has multithreading on. That function `parallelForEach`s only nested operations that have their own pass manager. `Simplify::buildRound` parses every step into a `ModuleOp` pass manager, and `SymbolsHeld` does the same, so the adaptor's work list stays empty. `PassManager::run` still calls `enterMultiThreadedExecution`, which is why the pool exists and why its workers wait.

## What the trace measured

A 64s Tracy sample from process start, compiler thread, 45,303 samples:

| where | samples | share |
| --- | ---: | ---: |
| `mlir::parseSourceFile` | 32,823 | 72% |
| `Simplify::runOnOperation` | 11,851 | 26% |

Inside the simplify slice:

| where | samples | share of the slice |
| --- | ---: | ---: |
| `OperationVerifier::verifyOpAndDominance` on the stack | ~53% | |
| `markLoopBreakers` | 2,430 | 20.5% |
| `idr::graph::components` | 1,217 | 10.3% |
| `refersTo` | 719 | 6.1% |

`stronglyConnected` does not appear. No simplify leaf is above about 1.4%. Only `optMain` runs compiler work. Pool threads are idle in `condition_variable::wait`.

The 72% parse share means the simplify samples are the start of the first round, not a finished round and not the three minutes between this window and the 240s kill. Those later minutes were not sampled. The measured split already accounts for a kill that never sees `compile()` return: parsing this file is most of the first minute, and the simplify time that follows is a verifier walk plus the breaker graph, repeated for every step of the round that rewrites.

## Measured, and read from code

Measured, and not re-derived here: the module's size and shape, the stage-0 Chez run (137 s, 9.1 GB), the 240s SIGKILL with empty stderr, when `-mlir-timing` prints, and the Tracy counts above.

Read for this note: `foreign/idr/lib/Simplify/Pass.cc`, `Round.cppm`, `Breakers.cppm`, `Breakers/Pass.cc`, `Trace.cppm`, `foreign/idr/lib/Facts/Pass.cc`, `Identity/Pass.cc`, `Inline/Pass.cc`, `Specialize/Pass.cc`, `Canonicalize/Pass.cc`, `foreign/idr/lib/Graph/RefersTo.cppm`, `Scc.cppm`, `foreign/idr/include/idr/Passes.td`, `mlir/lib/Transforms/CompositePass.cpp`, `mlir/lib/Pass/Pass.cpp` (`runPipeline` and `OpToOpPassAdaptor::runOnOperationAsyncImpl`), `mlir/lib/IR/Verifier.cpp` (`verifyOpAndDominance`), and the absence of `markAllAnalysesPreserved` in `SCCP.cpp`, `SymbolDCE.cpp`, `RemoveDeadValues.cpp`, and `IntRangeOptimizations.cpp`.
