<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] A delayed case block is elaborated at a fresh type, not its hole's

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), the stock Idris
refuses every definition of `Lambda.idr` with `Can't solve constraint
between: String and ?caseTy` (*measured*, scratch build of 89ba32eb on
Chez 10.4.1). Each is a pattern-matching lambda, or a `case`, checked at a
`Lazy` function type, as `maybe`'s second argument is:

```idris
second : Maybe (String, String) -> String
second x = maybe "" (\(n, m) => m) x
```

The tutorial gives pattern-matching lambdas as Idris
(`docs/source/tutorial/typesfuns.rst`: "can pattern match, e.g.
`\(x, y) => x + y`"); the constructors' names play no part (a plain
`Pair` fails the same way). Upstream's open issue #3418 reports it. The
harness was bent around it before this patch (552cf2ec: "pattern lambdas
as cases").

## Cause

*read* at 89ba32eb. A pattern-matching lambda is a lambda over a `case`.
`checkCase` (`src/TTImp/Elab/Case.idr`) runs under `delayElab`
(`src/TTImp/Elab/Delayed.idr`), which, when the expected type is not yet
known, makes a hole `?delayTy` for it and returns that as the term's type.
The delayed elaborator is the closure `checkCase` built over its own
argument, the original `Nothing`, so when it runs `caseBlock` makes a
second, unrelated type `?caseTy`, abstracted over the case's own
scrutinee. No clause can solve it, and nothing relates it to `?delayTy`,
which the rest of the application has meanwhile unified with `String`.

## Patch

`idris.patch`, against 89ba32eb: `delayElab` passes the type it gave the
hole to the delayed elaborator (`Glued vars -> Core (Term vars, Glued
vars)`; `checkCase` is its one caller), and `checkCase` elaborates the case
block at that type. Verified on a scratch build of 89ba32eb with this
patch: `Lambda.idr` checks and prints `n=7` and `b`, and the harness's
original `maybe` shapes check. See `## Testing` for the build carrying
every Idris patch, which builds Idris's own libraries with it.

## Testing

On a full bootstrap of 89ba32eb carrying 104 to 107, in order (scratch,
Chez 10.4.1, 2026-10-22), which built itself and all its libraries with
them; times are wall seconds on an 8-core Apple M2 Max virtual machine at
load average 5 to 15, the unpatched build's runs stopped at 120 s.

- `Lambda.idr` checks and prints `n=7` and `b` (unpatched: all three
  definitions refused).
- `Update.idr` of 108, a different bug, is still refused, its message
  naming `?delayTy` where the unpatched build named `?caseTy`.

Upstream's own tests in the groups basic, casetree, coverage, error,
evaluator, failing, interface, linear, perf, reg, termination, total and
with, run as upstream's runner runs them: 391 of 392 pass, as all 392 do on the unpatched build. The one
difference is `casetree/heuristics001`, which prints a compile-time tree:
105 leaves out an alternative `S` under a default that `S` has already
missed (dead: the variable is neither `Z` nor `S` there), and the
generated names after it shift.

## When it goes

When the Idris pin carries upstream's fix for #3418 (the check then passes
without the patch). Until then our code writes its pattern-matching
lambdas as Idris allows them, and the bootstrap applies the patch.

Our type checker (compiler/checker) carries the change as its own code, in
`TTImp.Elab.Delayed.delayElab`, whose elaborator always takes the hole's
type, which `tests/checker-delayed-case-expected-type` checks; it stays
when the patch goes.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn comments
on #3418, in their own words, is their call. The patch goes when the pin moves
past upstream's fix, which `tests/upstream-delayed-case-expected-type`
shows by passing on an unpatched pin.
