<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] The coverage check refutes a missing case only by a type no constructor's return type fits

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), the stock Idris
with 96 and 104 to 110 (the toolchain's) refuses covering definitions in
which a `Refl` matched inside a pair, or inside a case block's scrutinee,
refines an argument (*measured*, a scratch build of 89ba32eb on Chez
10.4.1, and the toolchain's):

- `CaseBlock.idr`: `0 alone`, `aloneKept` and `0 closedBelow` are "not
  covering", each by a call of its case block. `alone` is the frontend's
  `Held.aloneWritten` as INT-16 reduced it (its `repro/Alone.idr` and
  `AloneKept.idr`); `closedBelow` has the shape of `Graph.landsInto`.
- `Clause.idr`: `paired _ (_, Refl)` is reported missing `paired (S (S _))
  _` and `paired 0 _`; `0 lteSuccCases`, the frontend's
  `Held.lteSuccCases` with its second clause's `k'` written `_` (INT-16's
  `repro/LteSucc.idr`), is reported missing `lteSuccCases _`; `endless`
  and `up` are reported missing their `False` case.

Each case reported is impossible. INT-16 met the shape on every build of
the frontend: `Held` 342 and 387, `Graph` 798 to 816 (`landsInto`,
`joinedOver`, `intoClosed`), and in deeper case blocks in `Covers` (1252,
1733, 1834), which were not reduced.

## Cause

*read* at 89ba32eb. A pattern variable that a match on `Refl` refines,
written `_` in a clause, or an argument of a case function, which binds
each variable of its environment as `n@_` (`src/TTImp/Elab/Case.idr:296`),
takes the unifier's solution as its pattern: a constructor, matched, not a
forced pattern (only a dot pattern the user writes is `Dotted`,
`src/TTImp/Elab/Dot.idr:29`). So the coverage tree splits it, and every
other constructor of its type is proposed as missing, with the argument
holding the equation unsplit: `paired 0 _`, whose `_` is a `(Nat, 0 = 1)`.
A proposed case is refuted when its left-hand side does not elaborate or
one of its pattern variables has an empty type (`checkImpossible`,
`src/TTImp/ProcessDef.idr:1001`, by `hasEmptyPat`, 353 to 364), and
`isEmpty` (`src/Core/Coverage.idr:133` to 149) calls a type empty only
when the return type of every constructor of its family conflicts with it.
`(Nat, 0 = 1)` is empty, but `MkPair`'s return type fits it; only its
argument's type, `0 = 1`, conflicts with `Refl`'s. The same holds of the
triple `(x = 0, S (S _) = 1, y = 0)` in `alone`'s case, of the dependent
pair in `closedBelow`'s, and of `LTE (S (S k)) (S Z)`, which `LTESucc`
fits with an argument of the empty `LTE (S k) Z`. The case is reported, and
in a case block no clause can rule it out by hand, since the block's
patterns cannot name the variable its scrutinee refines.

## Patch

`idris.patch`, against 89ba32eb with 96 and 104 to 110, changes
`isEmpty` in `src/Core/Coverage.idr`, and the comment of `hasEmptyPat`
that describes it. A type is empty when no constructor of its family can
build a value of it: the constructor's return type conflicts with the
type, as before, or the constructor takes an argument whose type is
itself empty, each argument the return type determines replaced by what
the type has there (`MkPair`'s `b` by `0 = 1`; `LTESucc`'s `left` and
`right` by `S k` and `Z`). An argument its return type does not determine
stays a fresh name, which conflicts with nothing, so the search finds
less, never more. It looks into an argument's type only while that type is
smaller (in the nodes of its normal form) than the type it is an argument
of, so it ends: a family whose arguments do not get smaller (`Endless`,
whose `More` takes an `Endless`; `Up n`, whose `Climb` takes an
`Up (S n)`) is not taken apart again. The fresh names of each level are
numbered past those of the levels it is inside, so a substitution at one
level captures no other's.

The check refutes more proposed cases, and accepts more of a user's
`impossible` clauses, which the same test checks, and changes nothing
else: the tree, the cases proposed and the clauses matched are as before,
and a type the search calls empty has no value, since a constructor that
fits it needs a value of an empty type. `Missing.idr` misses a case,
`below (S _) _`, whose pair's `LTE (S _) 1` is inhabited by
`LTESucc LTEZero`; it is still refused, naming the case.

## Testing

On full bootstraps of 89ba32eb (scratch, Chez 10.4.1, 2026-10-23, this
repository's 8-core arm64 macOS machine), one with every Idris patch, 96
and 104 to 110, and one with this patch as well, each of which built
itself and all its libraries and ran the bootstrap's own targets, `make
bootstrap install install-api`, to the end: 482 s wall each, the two side
by side (bootstrap 339 s, install-api 140 s, alike), 3.0 GiB peak RSS
(rusage) each (*measured*). With the patch, Idris's own source, which
`install-api` checks, and its libraries check as before.

- `CaseBlock.idr` and `Clause.idr` check; without the patch, every
  definition in them but `three` is refused as above. INT-16's
  `repro/Alone.idr`, `AloneKept.idr` and `LteSucc.idr` check.
- `Missing.idr` is still refused, naming `below (S _) _`.
- upstream's own tests, in the 31 groups 108's README lists, run by
  upstream's runner as `make retest` runs it in the built tree (its
  failures file listing the groups): 731 of 733 pass with the patch and
  without it, the same two failing, `casetree/heuristics001` (105's) and
  `literate/literate006` (108's), and every test's result is the same.
  108's and 110's runs (724 of 734) also had eight failing that pass
  here, with and without the patch, run in the built tree: four chez
  tests that build from the source tree's `config.mk` and two codegen
  tests that print an `rm` complaint (96's README), and
  `literate/literate017` and `reflection/reflection024` (108's README).
  This run matched 733 tests to their 734.
- the other shapes INT-16 found are unchanged by the patch: `repro/Elem.idr`,
  `Scrut.idr` and `Refine.idr` are refused as before (the language's
  behaviour, not this bug).

The patch as it stands, changed since those runs only in the comment of
`hasEmptyPat`, was then built again the same way, applied by the
repository's series as the bootstrap applies it (476 s; bootstrap 334 s,
install-api 138 s; 2.9 GiB), and the check and the reproducers above,
rerun on it, give the same results.

The frontend's sites were not checked with the patch: L16 has since
rewritten `Held`'s two (`givenAlone`, a clause whose triple holds the
equation on an erased implicit, which 110's order covers; `lteSuccCases`
splitting the proof first), and `Graph`'s three keep the shape
`CaseBlock.idr`'s `closedBelow` reduces.

`tests/upstream-coverage-nested-empty-type` checks that the pinned Idris
accepts `CaseBlock.idr` and `Clause.idr` and still refuses `Missing.idr`,
naming its missing case.

## When it goes

When the Idris pin carries an upstream fix (the check then passes without
the patch), or when nothing of ours meets the shape. Until then the
bootstrap applies the patch.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in his own words, is his call; upstream has labelled coverage
reports of a related shape "expected behaviour" (#402, where a nested
case splits what one clause does not). The patch goes when the pin moves
past upstream's fix, which `tests/upstream-coverage-nested-empty-type`
shows by passing on an unpatched pin.
