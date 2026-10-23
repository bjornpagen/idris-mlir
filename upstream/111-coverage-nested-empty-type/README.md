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
- `Joint.idr` (INT-18, with this patch's first form, 2026-10-23):
  `atHead` and `0 atNamed` are "not covering" by their case blocks, and
  `clauses` is reported missing `clauses (MkHead Nothing (_ :: _)) _`,
  though `written`, the same with that case as an impossible clause,
  checks. `atHead` is INT-18's `repro/CovG.idr`; `atNamed` has the shape
  of the frontend's `Proof/Covers.idr` `atNamedType` (INT-18's
  `repro/CoverNested.idr` and `CoverNestedCase.idr`), the one site the
  first form left (1754 at 366a9a22, still at 57c45e61).

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

`Joint.idr`'s cases are empty only by two parts together. In `atHead`
the Refl refines `r` to `MkHead Nothing []`, and the case proposed,
`MkHead Nothing (y :: z)`, has the scrutinee unsplit, of type `(ts ** (MkHead
Nothing (y :: z) = MkHead Nothing ts, AllR [] ts))`. `ts` is the first
part, which the type does not determine; each of the pair's parts has a
value for some `ts` (`Refl` fits the first, `Nil` the second), and none
for one `ts`: the equation holds `ts = y :: z`, and `AllR [] (y :: z)` is
empty. Written as an impossible clause the case is refuted by
elaborating its `Refl` pattern (`written`); the first form looked into
each part's type on its own, and so did not refute it.

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
`Up (S n)`) is not taken apart again.

A constructor that fits also says what its return type holds of the
type: two parts of the type it puts at one of its arguments are equal
(`Refl`'s two sides). A type with one constructor holds what that
constructor holds and what its arguments' types hold (a pair's parts'); a
type with more holds nothing here. Under what the arguments' types hold,
a constructor's arguments are looked into again: a fresh name equal to a
term it does not occur in stands for that term, two applications of one
constructor are equal where their arguments are, an equation of any
other shape says nothing, and each argument's type that names a fresh
name so solved is looked into with the term put in; if one is empty, the
constructor cannot build a value. In `atHead`'s case, the pair's
equation holds `ts = y :: z`, under which its `AllR [] ts` is empty. The
second look is into the same arguments, again only while each is smaller
than the type, so the search still ends. Every fresh name of the whole
search is numbered past every other, so putting what one stands for into
a type captures none.

The check refutes more proposed cases, and accepts more of a user's
`impossible` clauses, which the same test checks, and changes nothing
else: the tree, the cases proposed and the clauses matched are as before,
and a type the search calls empty has no value, since a constructor that
fits it needs a value of an empty type. An equation a type with one
constructor holds holds of every value of it, a fresh name stands for one
value of an argument, and only what constructor equality gives is drawn
from it, so an argument's type read under it is that argument's type.
`Missing.idr` misses two cases: `below (S _) _`, whose pair's `LTE (S _)
1` is inhabited by `LTESucc LTEZero`, and `upToOne (MkHead Nothing (_ ::
_)) _`, whose value `MkHead Nothing [t]` has `([t] ** (Refl, LTESucc
LTEZero))`: read under its equation's `ts = t :: _`, the bound still has
a value. Both are still refused, each naming its case.

## Testing

The patch as it now stands, with the equations across arguments
(INT-18's R-u, 2026-10-23), on full bootstraps of 89ba32eb (scratch, Chez
10.4.1, this repository's 8-core arm64 macOS machine), one with the Idris
series as the toolchain carries it (96 and 104 to 112, this patch's first
form among them) and one with the whole series as it now stands (96 and
104 to 114, this patch amended), each of which built itself and all its
libraries and ran the bootstrap's own targets, `make bootstrap install
install-api`, to the end: 469 s wall (bootstrap 328 s, install-api 137
s) and 502 s (355 s and 143 s, beside a run of upstream's tests on the
first), 2.9 and 3.0 GiB peak RSS (rusage) (*measured*). With the series, Idris's own source, which
`install-api` checks, and its libraries check as before.

- `Joint.idr` checks; with the first form, `atHead`, `atNamed` and
  `clauses` are refused as above. INT-18's `repro/CovG.idr`,
  `CoverNested.idr` and `CoverNestedCase.idr` check; `CovA.idr` to
  `CovF.idr` check, as before.
- `CaseBlock.idr` and `Clause.idr` check, and `Missing.idr` is refused,
  naming `below (S _) _` and `upToOne (MkHead Nothing (_ :: _)) _`, with
  either form.
- the frontend's `Proof/Covers.idr` at dbb63119, `atNamedType` as
  written, checks (INT-18's supplementary export, its scratch for this
  site taken out); with the toolchain's Idris it is refused, not
  covering, as INT-18 reports.
- upstream's own tests, as below: 731 of 733 pass with either series, the
  same two failing, and every test's result is the same (114's README).

The first form, on full bootstraps of 89ba32eb (scratch, Chez 10.4.1,
2026-10-23, this repository's 8-core arm64 macOS machine), one with every
Idris patch, 96 and 104 to 110, and one with this patch as well, each of
which built
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

The first form, changed since those runs only in the comment of
`hasEmptyPat`, was then built again the same way, applied by the
repository's series as the bootstrap applies it (476 s; bootstrap 334 s,
install-api 138 s; 2.9 GiB), and the check and the reproducers above,
rerun on it, gave the same results.

The frontend's sites were not checked with the patch: L16 has since
rewritten `Held`'s two (`givenAlone`, a clause whose triple holds the
equation on an erased implicit, which 110's order covers; `lteSuccCases`
splitting the proof first), and `Graph`'s three keep the shape
`CaseBlock.idr`'s `closedBelow` reduces.

`tests/upstream-coverage-nested-empty-type` checks that the pinned Idris
accepts `CaseBlock.idr`, `Clause.idr` and `Joint.idr` and still refuses
`Missing.idr`, naming its two missing cases.

## When it goes

When the Idris pin carries an upstream fix (the check then passes without
the patch), or when nothing of ours meets the shape. Until then the
bootstrap applies the patch.

Our type checker (compiler/checker) carries the first form as its own
code, in `Core.Coverage.isEmpty`, which
`tests/checker-coverage-nested-empty-type` checks, and
`tests/checker-coverage-nested-empty-type-missing` that it still refuses
`Missing.idr`'s first shape; it stays when the patch goes. The equations
across arguments are not yet its own: they go into its `Fit` and
`fitting` (`src/Core/Coverage.idr`, 142 to 166: what a fit holds),
`emptyFrom` (232: what a type with one constructor holds), `cannotBuild`
(250: the second look under what the arguments hold) and `emptyArg` (265),
with the fresh names numbered across the whole search; its fix is its
own code, as every fix there is.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in their own words, is their call; upstream has labelled coverage
reports of a related shape "expected behaviour" (#402, where a nested
case splits what one clause does not). The patch goes when the pin moves
past upstream's fix, which `tests/upstream-coverage-nested-empty-type`
shows by passing on an unpatched pin.
