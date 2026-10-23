<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] A type binds an unsolved implicit argument before matching the constraint that solves it

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), the stock Idris
with 96 and 104 to 112 (the toolchain's series), and unpatched, refuses
every definition of `Matched.idr` (*measured*: a scratch build of the
series on Chez 10.4.1, and INT-18's unpatched control for the frontend's
shape):

```
Error: While processing type of sameFirst. Can't solve constraint between: ?xs [no locals in scope] and as.
```

Each type applies a function whose implicit argument only a postponed
constraint between two applications of one function solves:
`firstOf : P (xs ++ ys) n -> P xs n` applied to `w : P (as ++ bs) n` gives
`as ++ bs` against `?xs ++ ?ys`. The same term on a right-hand side checks
(INT-18's `repro/PlacedRhs.idr`), and so does the type with both
implicits stated; with one stated it is refused too (`statedRest`, `ys`
stated), though the constraint then determines the other alone. `placed` has the frontend's shape, an
index that reduces to an append (`g (x :: xs)` is `h x ++ g xs`). INT-18
met it in `Proof/Describes.idr`'s `firstPart` (`placedFirst w`, `w`'s
index reducing to `recursions t ++ recursionsIn ts`), with cascades in
`firstPart`'s right-hand side and `coverAll`, at 366a9a22 and still at
57c45e61. 0639a573 (L16do) states `ys` there, `placedFirst {ys =
recursionsIn ts} w`, which the stock Idris accepts because `carriedAt`'s
parameter fixes `xs`: a workaround of this bug, which with the patch is
not needed (measured on the scratch builds below, the site as first
written).

A type's implicit arguments are inferred as a term's are, and an
implicit is bound as an argument of the type when inference fails: "If
inference fails for `_`, we implicitly bind a new name", and "it's okay
for a hole in a type as long as it's resolved by the time the definition
is done" (`docs/source/implementation/overview.rst`, 332-333 and
308-309). Here inference has not failed when the name is bound: the step
that solves it has not run yet.

## Cause

*read* at 89ba32eb. In a type, an application registers each implicit
argument's hole to be bound if it stays unsolved (`addBindIfUnsolved`,
`src/TTImp/Elab/App.idr:189`). `++` is no constructor, so the unifier
postpones `as ++ bs` against `?xs ++ ?ys` (`unifyApp`,
`src/Core/Unify.idr:913`, by `unifyIfEq`, 629); only in match mode, or
in a search, does `unifyBothApps` unify the arguments of two
applications of one name (1017 to 1030). A term's elaboration ends
(`elabTermSub`, `src/TTImp/Elab.idr:126` to 147) by solving constraints,
retrying delayed elaborators, retrying the constraints in match mode
(136), which solves `?xs = as` and `?ys = bs`, and then defaults and a
last chance. A type is checked under `IBindHere` (`checkBindHere`,
`src/TTImp/Elab/ImplicitBind.idr:539`): it solves constraints, retries
delayed elaborators and polymorphic patterns and then defaults (556 to
575), and `getToBind` (322) calls `bindUnsolved` (126), which binds every
registered hole still unsolved as a new implicit of the outer
environment, where none of the type's locals is, and unifies the hole
with it. The match retry runs after, in the declaration's own
`elabTermSub`, when `?xs` stands for a name bound outside `as`, which no
solution can then equal: "?xs [no locals in scope] and as".

## Patch

`idris.patch`, against 89ba32eb (no other patch of the series touches
the file), changes `checkBindHere`: for a type (the `PI` bind mode) it
retries the constraints made while checking it in match mode before its
defaults and before binding, in the order a term's elaboration takes. A
left-hand side and the coverage check's (`PATTERN` and `COVERAGE`), where
an unsolved implicit becomes a pattern variable rather than an argument
of a type, keep upstream's order.

Our type checker (compiler/checker), Idris's copied into our tree, has
the same `checkBindHere` (its `src/TTImp/Elab/ImplicitBind.idr`, 544: the
defaults solved at 578 to 580 after the polymorphic patterns at 574 to
575, then `getToBind` at 586); its fix is its own code, as every fix
there is.

Only constraints still postponed are retried, and match mode solves a
hole only where the arguments of two applications of one name unify,
as the declaration's `elabTermSub` does just after. What changes is that
a hole such a constraint solves is solved, as on a right-hand side, and
not bound. A hole that no constraint relates is still bound as an
implicit (`Generalised.idr`: `tagged` takes a `Tag []` of any element
type, with the patch and without it), and a constraint that no match
solves is still an error (`Unmatched.idr`: `rev as` against `?xs ++ ?ys`,
refused with the same message with the patch and without it).

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

- `Matched.idr` checks; without the patch `sameFirst` and `statedRest`
  are refused as above, and `placed` for `?xs [no locals in scope]`
  against `h x`. INT-18's `repro/PlacedUnbound.idr`, `PlacedBound.idr` and
  `ImplicitLocal.idr` to `ImplicitLocal4.idr` check; `PlacedRhs.idr`
  checks, as before.
- `Generalised.idr` checks, and `Unmatched.idr` is refused, `Can't solve
  constraint between: rev as and ?xs ++ ?ys`, with the patch and without
  it.
- the frontend's `Proof/Describes.idr` at dbb63119, `firstPart` as
  written, checks (INT-18's supplementary export, its scratch for this
  site taken out); with the toolchain's Idris it is refused as INT-18
  reports.
- upstream's own tests, in the 31 groups 108's README lists, run by
  upstream's runner as `make retest` runs it in the built tree: see
  114's README, which reports the run of the whole series.

`tests/upstream-type-implicit-binding-order` checks that the pinned Idris
accepts `Matched.idr` and `Generalised.idr` and refuses `Unmatched.idr`
for its constraint. Its run script, run directly against each scratch
build (`IDRIS_MLIR_TOOLCHAIN` naming a directory whose `idris2` is that
build's prefix), prints its expected output with the patch, and without
it the `Matched` line that says the bug still reproduces.

## When it goes

When the Idris pin carries an upstream fix (the check then passes
without the patch; upstream main has the same `checkBindHere` on
2026-10-23), or when nothing of ours meets the shape. Until then the
bootstrap applies the patch.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in their own words, is their call. The patch goes when the pin
moves past upstream's fix, which `tests/upstream-type-implicit-binding-order`
shows by passing on an unpatched pin.
