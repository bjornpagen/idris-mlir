# `idr-simplify` does not finish on the frontend module

The simplify loop stops (max-rounds 64 runs one extra round, then stops, or
it stops when OperationFingerPrint is unchanged). It is not an open loop. A
4-minute kill never sees compile() return because one round on the
58,349-function frontend module walks the whole module many times, and any
pass that does not call markAllAnalysesPreserved() then verifies the whole
module. The 64-second trace is still inside the first of those verifies, on
one thread, in idr::verify::program, after round 1's loop breakers mark the
cycles Emit did not mark. sccp, int-range-optimizations, remove-dead-values,
and symbol-dce verify again even when they change nothing. -mlir-timing
prints only when compile() returns, so stderr was empty. Stage 0 stays 137 s,
9.1 GB. stronglyConnected is no longer on the breaker path.

`Simplify::runOnOperation` in `foreign/idr/lib/Simplify/Pass.cc` runs one
composite fixed-point over the pipeline from `simplifyRound()` in
`foreign/idr/lib/Simplify/Round.cppm`. The composite pass keeps an
`OperationFingerPrint` and stops when a round leaves it unchanged.
`max-rounds` defaults to 64. Once that budget is spent the composite runs one
extra pipeline, then returns. `Simplify::exhausted` then emits
`unsupported (compile-time budget)`. The four-minute kill is still inside
round 1, so that check never runs.

`Round.cppm` runs, in order: `idr-loop-breakers`, `idr-effects`,
`idr-identity`, `idr-inline`, `idr-specialize`, `sccp`,
`int-range-optimizations`, `idr-canonicalize`, `cse`, `remove-dead-values`,
`symbol-dce`. Breakers are `foreign/idr/lib/Simplify/Breakers.cppm` and
`foreign/idr/lib/Simplify/Breakers/Pass.cc`. `markLoopBreakers` reads each
body once, builds the inlinable graph from `idr::graph::refersTo`, and marks
cycles with `idr::graph::components`. Emit left those cycles unmarked, so
round 1's breakers rewrite, and the verify after that pass is the first
whole-module verify. `idr::graph::stronglyConnected` is not on this path.

After each pass, `OpToOpPassAdaptor::runPipeline` in `mlir/lib/Pass/Pass.cpp`
verifies when `verifyPasses` is set (the pass-manager default) and
`preservedAnalyses` is not everything. The idr dialect verifier then calls
`idr::verify::program`
(`foreign/idr/lib/Verify/Program.cppm`, reached from
`foreign/idr/lib/Dialect/Verify/Attributes.cc`). On this module that walk
covers every nested operation of all 58,349 functions. The 64-second sample
is inside that first call, on the compiler thread. The pool threads wait.

Our steps call `markAllAnalysesPreserved` when they changed nothing:
breakers, effects, identity, the inliner, specialize, canonicalize, and the
`SymbolsHeld` wrapper in `Pass.cc`. `sccp`, `int-range-optimizations`,
`remove-dead-values`, and `symbol-dce` do not, so each of them verifies
again even when the module is unchanged. A `SymbolsHeld` wrapper that
preserves analyses does not cancel the verify inside the inner pipeline.
`cse` preserves every analysis only when it changed nothing.

The steps are module passes, so the adaptor has no nested pass managers to
run in parallel. One thread does each verify. The input is
`build/self/keep/front.mlir`, about 386 MiB, one module.
