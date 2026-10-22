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
retries the delayed elaborators in a recoverable pass and then in an
all-errors pass, and each pass re-elaborates every level nested inside,
so a failure deep in the nest is retried 2, 4, 8, ..., 128 times (counted
on an instrumented run). The failure counts as recoverable because
`contra`, which decides whether a mismatch can never be solved, does not
see that a term stuck on a bound variable can never become a function
type, a type or data constructor, `Type` or a constant.

## Why there is no patch

Not carried yet. A candidate, about twenty lines adding those cases to
`contra` (a stuck application of a bound variable against a rigid form is
a contradiction), applies at 89ba32eb but has not been built, measured or
run against upstream's test suite, and changing what counts as
recoverable can change which correct programs elaborate, so it is not
carried unverified. It would not cover slow failure on errors that involve
metas (upstream #2118). It is owed under D121; until it lands, such an
error is slow to report on the stock host, and nothing correct is refused.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in his own words, is his call. It becomes a carried `idris.patch`,
with its check, when ours is built and verified.
