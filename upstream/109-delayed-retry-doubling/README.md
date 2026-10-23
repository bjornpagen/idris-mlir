<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] A type error under nested delayed elaboration takes time exponential in the nesting to report

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), the stock Idris
takes 49 s of user time to report the type error in `Retry.idr`, a `do`
block of eleven pattern binds over a linear machine whose last line uses
`b`, which the first bind rebinds as a value, as a type (*measured*,
scratch build of 89ba32eb on Chez 10.4.1, load average about 15). At 6, 8,
9, 10 and 11 binds it takes 0.95, 3.83, 9.5, 20.7 and 53 s (load about
30), doubling per bind; the same block without the error checks in 0.49 s
at eleven. Correct code is unaffected: this is the slow failure the
prototype in `audits/p0/design/idris-linear-check.md` met (its
`recanonRow` has this error), not a cost of nested linear pairs.

## Cause

*read* at 89ba32eb, `src/TTImp/Elab/Delayed.idr`. Each bind's pattern
match is a delayed elaborator nested in the one before. `retryDelayed`
retries the delayed elaborators in a recoverable pass and then, when that
pass made no progress, in an all-errors pass, and each pass runs again
every level nested inside, which retries its own nest twice; so a failure
deep in the nest is run 2, 4, 8, ..., 128 times (counted on an
instrumented run) before the same error is reported. Where nothing the
failing elaborator depends on has changed between the passes, the second
run can only fail again.

The error is recoverable because `contra`, which decides whether a
mismatch can never be solved, does not call `v Nat` against `Type -> Type`
one. Making it do so (a term stuck on a bound variable against a type
former, a constructor, a function type, `Type` or a constant), the first
candidate, is wrong: a bound variable in the error can be a pattern
variable of a case block the delayed elaborator itself made, which a
retry, with more known, makes differently. A full bootstrap of 89ba32eb
with 104 to 107 and that candidate stopped in Idris's own `papers`
library, at `Data.Container`'s `fromCompose` (`p p1'` against
`... -> Void`, where `p` is `MkDPair`'s implicit bound by a pattern-matching
lambda whose scrutinee's type was not yet known), which the stock Idris
checks (*measured*, 2026-10-22). It was not carried.

## Patch

`idris.patch`, against 89ba32eb with 104 to 107: `retryDelayed'` keeps,
for each delayed elaborator that failed recoverably, its error and the
metavariables (holes and guesses) unsolved when the failing attempt began.
An attempt that would begin with all of those still unsolved knows no more
than the one that failed, so it is not run: the kept error stands for it,
in either pass. Any solution since (by another elaborator, by
`solveConstraints` between the passes, or by the failed attempt itself)
runs it again, as before. So only a run whose outcome is already known
is skipped, which programs check does not change, and the error reported
is the one the skipped run would have given (*conjecture*: it rests on
elaboration giving the same result from the same solved metavariables,
which the byte-identical errors below and the unchanged test results
bear out).

## Testing

On full bootstraps of 89ba32eb (scratch, Chez 10.4.1, 2026-10-22, an
8-core Apple M2 Max virtual machine at load average about 4), each of
which built itself and all its libraries (prelude, base, contrib, network,
test, linear, papers): one with 104 to 107, one with 104 to 107 and this
patch, and one with 96, 104 to 107 and this patch.

- `Retry.idr` reports its error in 0.29 s of wall time, at 6, 8, 10 and
  11 binds alike (0.27, 0.31, 0.30, 0.29 s); with 104 to 107 alone, 6 and
  8 binds take 0.86 and 3.74 s. The error printed is the same, byte for
  byte, at 6 and 8 binds. The block without the error checks in 0.44 s.
- Upstream's own tests in the groups basic, casetree, coverage, error,
  evaluator, failing, interface, linear, perf, reg, termination, total and
  with, run as upstream's runner runs them: 391 of 392 pass, on the build
  with 104 to 107 and this patch and on the one with 96 too, as with 104
  to 107 alone (104's README); the one difference from the unpatched
  build is `casetree/heuristics001`, 105's. With every Idris patch, 96
  and 104 to 109, those groups and eighteen more pass as they do without
  96, 108 and 109 but for 108's `literate/literate006` (108's README).

`tests/upstream-delayed-retry-doubling` checks that the pinned Idris
reports `Retry.idr`'s error within a twenty-second limit.

## When it goes

When the Idris pin carries an upstream fix that reports such an error
without running its nest again. Until then the bootstrap applies the
patch.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in his own words, is his call. The patch goes when the pin moves
past an upstream fix, which `tests/upstream-delayed-retry-doubling` shows
by passing on an unpatched pin.
