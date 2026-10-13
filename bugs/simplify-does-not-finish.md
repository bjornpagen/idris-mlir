# `idr-simplify` does not finish on the frontend module

**Status:** open until it is measured again on the cutover (proposal
0015). The record below was read and measured at 25890d32, before it.

The loop was not open: it stops after `max-rounds` (64) and one more
round, or at a round that leaves the composite's fingerprint unchanged.
A 4-minute kill never saw compile() return because one round on the
58,349-function frontend module walked the whole module many times, and
the first whole-module verify had not finished after 64 seconds. The
sample was inside the dialect's program verifier, on one thread, right
after round 1's loop breakers marked the cycles Emit had not marked; the
pool threads waited. `-mlir-timing` prints only when compile() returns,
so stderr was empty. The input is `build/self/keep/front.mlir`, about
386 MiB, one module. Stage 0 itself stays 137 s at 9.1 GB.

Why each verify covered the whole module: every step of the round was a
module pass, so the pass manager had no nested managers to run in
parallel, and after each pass that did not mark every analysis preserved
it verified the module, whose attribute verifier ran every per-function
rule. `sccp`, `int-range-optimizations`, `remove-dead-values` and
`symbol-dce` mark nothing preserved, so each verified again even when the
module was unchanged; the steps of ours that changed nothing marked
everything.

What the cutover changes: the round's function step runs per function in
parallel, and the verifier after a function pass checks only its
function; the per-function rules are `idr.func`'s region verifier, which
the module's verifier runs per function in parallel, as MLIR does; and
the program verifier keeps only the module-level rules. Upstream's four
passes still verify the module after each run. The qualification records
the verifier's share of a round and the round count on this module; that
record closes this report or names what is left.
