<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] A case that splits a bound variable takes the constraints on it out of the pattern fragment

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), the stock Idris
refuses two well-typed definitions (*measured*, scratch build of 89ba32eb
on Chez 10.4.1):

- `Update.idr`: a record update in a lambda whose type is inferred,
  `let keep = \pool => { runs $= map S } pool in map keep pools`: "Can't
  solve constraint between: Pool and ?caseTy".
- `Hint.idr`: `map (\k => { threads := k } o) (parsePositive n)`, where
  `threads : Nat`: "Mismatch between: Integer and Nat".

The same definitions check with the lambda annotated, with no `case` (a
constructor applied instead of an update), or with the case on `id o`
instead of `o`: only a case that splits a bound variable fails. Upstream's
issue #62, opened by its author, reports the family ("case in a lambda is
broken"). The harness was bent around both before (552cf2ec: `keep`
given a signature, `parsePositive {a = Nat}`).

## Cause

*read* at 89ba32eb, `src/TTImp/Elab/Case.idr`. A record update is a
`case` on the record. `caseBlock` elaborates the case as a function over
the environment and splits the scrutinee where it is a bound variable,
so in each clause the variable is replaced by the constructor pattern,
in the spine of every still-unsolved meta applied to it: the lambda's
result type in `Update.idr`, `parsePositive`'s `a` in `Hint.idr`. A
constraint between such a meta and a type is then outside the pattern
fragment, so it is postponed and never solved; in `Hint.idr` the
`%defaulthint` for `Num` fires meanwhile, fixing `a` as `Integer`
against the field's `Nat`.

## Why there is no patch

Not written yet. The fix is in how `caseBlock` treats a meta applied to
the variable it splits (abstracting the meta over the variable, not over
its pattern, or solving the outer constraint first), a redesign of that
step rather than a local change, and it has not been attempted or built.
It is owed under D121: our code is not bent around it, and until the patch
lands the two shapes fail on the stock host.
`tests/upstream-case-split-pattern-fragment` checks that the pinned Idris
still refuses both; it fails, and goes, once a carried patch or the pin
fixes them.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn comments
on #62, in his own words, is his call. The report goes when the pin
carries upstream's fix; it becomes a carried `idris.patch` when ours is
written and verified.
