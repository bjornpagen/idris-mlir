<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] The coverage check of an erased function splits its erased indices first

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), the stock Idris,
unpatched and with 96 and 104 to 109, refuses three total definitions
(*measured*, scratch builds of 89ba32eb on Chez 10.4.1):

- `Marker.idr`: `0 mappedDrops` is "not covering", "Missing cases:
  mappedDrops _ _" three times. Each named case is impossible: the
  implicit image `f'` the message hides is `Loc`, `Nm` or `App`, which a
  `Mapped f f'` gets only from a term of the same head or from a marker
  (`Nm True s`), and `Drops f` holds of neither. The same definition
  without its `0` checks.
- `Contracts.idr`: `0 mappedContracts` is "not covering", naming 1383
  cases, each `mappedContracts _ _` (2.9 s; 8.5 s without 105).
- `CaseBlock.idr`: `0 erasedReduces` is "not covering", naming cases
  `erasedReduces IsPlaceholder (AnErased _)`, each impossible; with the
  function's own tree mended, its case block (on a proof that the
  intermediate term is `Er`) is not covering in the same way.

Our code met all three (INT-13, INT-15). In the type checker's
`Idris/Host.idr`, eleven erased proofs over the `Mapped` relation
(`mappedSpine`, `mappedConstants`, `mappedComputes`, `mappedDrops`,
`mappedFloats`, `mappedMisses`, `mappedReduces`, `mappedAllReduce`,
`mappedBinderReduces`, `mappedPiReduces`, `mappedMatches`) were refused
naming only such cases, and the coverage check of `mappedContracts`, the
fourteen-clause `Contracts` case, ran past 300 s and 8 GiB (its case tree
takes 0.29 s). In the frontend, 25 more: seven in `Proof/Reading.idr`,
six in `Translate/Contraction.idr`, two in `Proof/Bound.idr`, one in
`Proof/Weights.idr`, three in `Proof/Inversion.idr` (`funcHead`'s and
`erasedReduces`' case blocks, `inertOne`) and six in
`Growth/Template.idr`.

## Cause

*read* at 89ba32eb, `src/Core/Case/CaseBuilder.idr`,
`src/TTImp/ProcessDef.idr` and `src/Core/Coverage.idr`. The coverage
check builds a compile-time case tree from the clauses (`checkCoverage`,
`getPMDef (CompileTime mult)`) and proposes, as missing, the patterns of
every path the tree leaves unmatched (`getMissing`); each is refuted when
its left-hand side does not elaborate or one of its pattern variables has
a type no constructor can inhabit (`checkImpossible`, `hasEmptyPat`), or
dropped when a clause matches it (`checkMatched`).

A compile-time tree takes the arguments from the left (`nextIdxByScore`
at `CompileTime`). In an erased function it may split an erased argument
(`getClauseType` treats an erased constructor pattern as a split only
there), and the indices come before the arguments whose types name them:
an erased proof binds its implicit indices before its explicit
arguments, and a case block takes its environment, an intermediate term
among it, before its scrutinee. So the coverage tree splits the indices
first. Where an index's value has no clause the path ends unmatched with
the arguments that determine it unsplit, and the case proposed has them
as pattern variables whose types are not empty one by one: in
`Marker.idr`, with `f' = Loc`, `m : Mapped f (Loc k)` has two
constructors (`MLoc` and the marker's) and `d : Drops f` is empty only
once `f` is known. Refuting it needs a split of `m`, which nothing makes,
so it is reported, its explicit arguments `_` and the index hidden. And
`getMissing` walks the tree under each default once for every
constructor the default stands for (`replaceDefaults`), so a tree whose
defaults nest, as one that splits every clause's indices first does, is
walked a number of times exponential in the nesting: for
`mappedContracts` it looked up a type's constructors 1.13 million times
in 400 s without finishing.

## Patch

`idris.patch`, against 89ba32eb with 104 to 109, changes the order an
erased function's coverage tree splits in, and nothing else.
`CompileTime` carries a `SplitOrder`: `FromLeft` for the tree a
definition is evaluated by, built as before; `KeptFirst` for an erased
function's coverage tree, which takes next the leftmost argument whose
multiplicity is not 0, an argument a run would keep, and when there is
none the rightmost: a later argument's type names the earlier ones, so
the later determine the earlier. Every pattern is still split, so the
tree still covers exactly what the clauses cover, and every case it
proposes is still checked as before; what changes is which cases it
proposes. With the determining arguments split first, the indices are
split where the clauses' patterns have fixed them, a case proposed has
those patterns, and elaborating it refines the indices by unification,
which refutes the impossible ones.

The tree a definition is evaluated by, and so what reduces at compile
time, does not change, nor does the coverage tree of a function a run
keeps. Such a function matches an erased argument only where the
patterns before it force it, which its tree tells by taking the
arguments from the left (`getClauseType`); with the kept arguments first
for every function, the bootstrap refused Idris's own `libs/papers`
(`Language.IntrinsicTyping.Krivine`, the `with` block of `refocus`),
whose erased trace argument was then split where it is forced. An erased
function's tree splits every erased constructor pattern, so the order
cannot change what it splits.

## Testing

On a full bootstrap of 89ba32eb with every Idris patch, 96 and 104 to
110 (scratch, Chez 10.4.1, 2026-10-22, an 8-core Apple M2 Max virtual
machine), which built itself and all its libraries (prelude, base,
contrib, network, test, linear, papers) and ran the bootstrap's own
targets, `make bootstrap install install-api`, to the end:

- `Marker.idr`, `Contracts.idr` (in 0.7 s) and `CaseBlock.idr` check.
- a definition that does miss a case is still refused, now naming it:
  `Marker.idr` without its `MTy` clause reports `mappedDrops MTy _` (the
  unpatched build: four cases, each `mappedDrops _ _`).
- `Covering.idr` (104) and 108's reproducers check.
- the type checker of INT-13's export (15371331), checked against the
  libraries its other modules were built with: the eleven proofs and
  `mappedContracts`, restored from the source, check in 23 s and 1.9 GiB
  for the module; its pristine `Idris/Host.idr` checks in 25 s, reporting
  only errors of its own (`substitutesMarkers`, `shiftedInsert`,
  `shiftedSubst`, `substMiddleMapped`, `substitutes`, `putInMappedAdd`,
  `putInMapped`) and no coverage failure.
- the frontend of INT-15's export (3fe4b23a), each module checked with
  its 25 sites restored from the source and INT-15's other scratch kept:
  `Reading`, `Contraction`, `Bound` (its `lteRefl`, which base lacks,
  written out) and `Weights` check; `Inversion`
  checks but for `funcHead`, whose call of `refSpines` leaves an
  implicit unsolved, an error of its own, and no coverage failure;
  `Template` reports its sixteen other errors and none of its six
  coverage failures.
- upstream's own tests, run as upstream's runner runs them, in the 31
  groups 108's README lists: 724 of 734 pass, the same ten failing as on
  the build without this patch.

Times are wall seconds at a load average of 6 to 9 (other lanes' builds).

`tests/upstream-coverage-erased-index-first` checks that the pinned Idris
accepts the three reproducers.

## When it goes

When the Idris pin carries an upstream fix (the check then passes without
the patch), or when nothing of ours meets the shape. Until then our code
writes the proofs as Idris allows them, and the bootstrap applies the
patch.

Our type checker (compiler/checker) carries the change as its own code, in
`Core.Case.CaseBuilder` (`splitOrder`, `keptOrLast`), which
`tests/checker-coverage-erased-index-first` checks; it stays when the patch
goes.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in their own words, is their call. The patch goes when the pin moves
past upstream's fix, which `tests/upstream-coverage-erased-index-first`
shows by passing on an unpatched pin.
