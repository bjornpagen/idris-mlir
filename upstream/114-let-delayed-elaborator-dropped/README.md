<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] A let's value drops the delayed elaborators its case blocks leave

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), the stock Idris
with 96 and 104 to 112 (the toolchain's series), and unpatched, refuses
both definitions of `Let.idr` (*measured*: a scratch build of the series
on Chez 10.4.1, and INT-18's unpatched control for the frontend's shape):

```
Error: Unsolved holes:
Let.{delayed:845} introduced at:
Let:30:46--30:51
```

`empty` is ambiguous there (`Box.empty`, `Names.empty` and the prelude's
`Alternative` one), the start of a fold in a let's value whose step is a
case block, with `let ... in` and with a do block's `let`, which is its
translation. The same value checks as a definition's right-hand side,
with the name qualified, or with a step that matches nothing (INT-18's
`repro/EmptyFold.idr`, `EmptyFoldNoAmb.idr`, `EmptyFoldNoCase.idr`);
INT-18's `EmptyFoldLetIn.idr` checks only because its `let` block
declares a type and so is a local definition, elaborated as a definition
is. INT-18 met it in the frontend, `Growth/Graph.idr`'s `build` (2839,
2844 and 2849 at dbb63119; 2830, 2835 and 2840 at 57c45e61), where
0639a573 (L16do) names `SortedMap.empty` at each, which the bug made
necessary and the patch does not.

The name is resolved by its type: Idris 2 disambiguates "between names
which have different concrete return types", postponing "resolution if a
name can't be resolved immediately", and where a concrete name is valid
in the context it is chosen (`docs/source/updates/updates.rst`, 259-263
and 292-294). Here the fold's start has type `Box` once the fold is
checked against `the Box`, and only `Box.empty` has it, as the
right-hand side form finds. The hole is neither a resolution nor an
ambiguity reported: the postponed resolution never runs.

## Cause

*read* at 89ba32eb. An ambiguous name whose type is not yet known is
elaborated later: a hole stands for it and its elaborator is queued with
the priority `Ambiguity` (`delayOnFailure`, `src/TTImp/Elab/Ambiguity.idr`,
370 and 423), and so is a case block whose type is not yet known, with
`CaseBlock` (`checkCase`, `src/TTImp/Elab/Case.idr:376`). A let's value
is checked under `runDelays (==CaseBlock)` (`checkLet`,
`src/TTImp/Elab/Binders.idr:250` and 257), which runs the value's case
blocks before its scope. `runDelays` (`src/TTImp/Elab/Delayed.idr:298`)
takes the value's queue, retries the ones with that priority, and puts
back the queue from before the value; the others are left in the state's
queue, which the first retried elaborator empties to keep track of its
own (`retryDelayed'`'s `attempt`, 248). So the ambiguous name's
elaborator is gone, and no retry around the let runs it. Without a case
block in the value nothing is retried and the queue survives; on a
right-hand side no `runDelays` takes the queue.

## Patch

`idris.patch`, against 89ba32eb with 107 and 109, which change the same
file, changes `runDelays`: the delayed elaborators it does not retry are
kept aside and put back, with the ones from before it, for the retries
around it, as they are when it retries none.

Our type checker (compiler/checker), Idris's copied into our tree, has
the same `runDelays` (its `src/TTImp/Elab/Delayed.idr`, 388: the value's
queue read at 400, those with the priority retried at 402 to 403, the
queue from before put back at 407, the attempt emptying the queue at
351; `checkLet` calls it at `src/TTImp/Elab/Binders.idr`, 257 and 262);
its fix is its own code, as every fix there is.

`runDelays` is called with a priority that filters only by `checkLet`;
`checkCase` and the elaborator reflection call it with `const True`,
retrying all, which this leaves as it was. In a let's value the
elaborators kept now run where every other postponed one does, in the
retries of the term around the let, so the name is resolved as on a
right-hand side, and where nothing fits the error is the one a
right-hand side gives: `NoneFits.idr`, whose fold is of type `Bool`, is
refused at `empty` for `Can't find an implementation for Alternative ?f`,
as the same value on a right-hand side is with or without the patch,
where without it the let form is refused for an unsolved `delayed` hole.

## Testing

On full bootstraps of 89ba32eb (scratch, Chez 10.4.1, 2026-10-23, this
repository's 8-core arm64 macOS machine), one with the Idris series as
the toolchain carries it, 96 and 104 to 112, and one with the whole
series as it now stands, 96 and 104 to 114 with 111 amended, each of
which built itself and all its libraries and ran the bootstrap's own
targets, `make bootstrap install install-api`, to the end: 469 s wall
(bootstrap 328 s, install-api 137 s) and 502 s (355 s and 143 s, beside a
run of upstream's tests on the first), 2.9 and 3.0 GiB peak RSS (rusage)
(*measured*). With the series,
Idris's own source, which `install-api` checks, and its libraries check
as before.

- `Let.idr` checks; without the patch both definitions are refused as
  above. INT-18's `repro/EmptyFoldDo.idr`, `EmptyFoldDo2.idr`,
  `EmptyFoldDo3.idr` and `EmptyFoldArg.idr` check; `EmptyFold.idr`,
  `EmptyFoldLetIn.idr`, `EmptyFoldNoAmb.idr` and `EmptyFoldNoCase.idr`
  check, as before.
- `NoneFits.idr` is refused for `Alternative ?f` at `empty`; without the
  patch, for the unsolved hole.
- the frontend's `Growth/Graph.idr` at dbb63119, `build` as written,
  checks (INT-18's supplementary export, its scratch for this site taken
  out); with the toolchain's Idris it is refused as INT-18 reports.
- with this site, 113's in `Proof/Describes.idr` and 111's in
  `Proof/Covers.idr` as written, the frontend's 102 modules typecheck
  with the whole series (INT-18's supplementary export at dbb63119, its
  scratch for errors of ours kept; 421 s for the 99 the driver imports,
  1.9 GiB).
- upstream's own tests, in the 31 groups 108's README lists, run by
  upstream's runner as `make retest` runs it in the built tree (its
  failures file listing the groups): 731 of 733 pass with the whole
  series and with the toolchain's, the same two failing,
  `casetree/heuristics001` (105's) and `literate/literate006` (108's),
  and every test's result is the same (501 and 503 s). The run is of the
  whole series, not of each patch alone.

`tests/upstream-let-delayed-elaborator-dropped` checks that the pinned
Idris accepts `Let.idr` and refuses `NoneFits.idr` at its ambiguous name,
not for a hole. Its run script, run directly against each scratch build
(`IDRIS_MLIR_TOOLCHAIN` naming a directory whose `idris2` is that build's
prefix), prints its expected output with the patch, and without it the
lines that say the bug still reproduces.

## When it goes

When the Idris pin carries an upstream fix (the check then passes
without the patch; upstream main has the same `runDelays` on
2026-10-23), or when nothing of ours meets the shape. Until then the
bootstrap applies the patch.

Our type checker (compiler/checker) now carries the change as its own
code, in `TTImp.Elab.Delayed.runDelays`, which
`tests/checker-let-delayed-elaborator-dropped` checks; it stays when the
patch goes.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in their own words, is their call. The patch goes when the pin
moves past upstream's fix, which
`tests/upstream-let-delayed-elaborator-dropped` shows by passing on an
unpatched pin.
