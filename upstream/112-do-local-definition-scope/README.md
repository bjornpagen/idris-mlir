<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] A do block's local definitions are bound as implicits in its later local types

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), the stock Idris
with 96 and 104 to 111 (the toolchain's series) refuses every definition
of `Local.idr` (*measured*, a scratch build of the series on Chez 10.4.1).
Each is a `do` block in which a typed local definition, `let v : T` and
then `v = ...`, names in `T` a local definition an earlier `let` of the
same block defines, or the same `let` block does:

```idris
twoLets : Nat -> IO Nat
twoLets n = do
  let xs : List Nat
      xs = [n, 0]
  let v : Vect (length xs) Nat
      v = fromList xs
  pure (length v)
```

`xs` in `v`'s type is bound as a fresh implicit, so `length xs` is
`length ?xs` and ambiguous between `List`'s, `Vect`'s, `SnocList`'s and
`String`'s. The same definitions written with `let ... in` check, nested
or as one block (INT-17's `repro/LocalType2.idr`). INT-17 met the shape
in the frontend, `Growth/Graph.idr`'s `build` (`let position : Vect
(length slots) Spot`, `slots` a typed local definition of the block),
which is the form L06d prescribed for a type that needs a value to
unfold (a local definition, not a let binding).

What the do block means is its translation: "`x <- v; e` becomes `v >>=
(\x => e)`" and "`let x = v; e` becomes `let x = v in e`"
(`docs/source/tutorial/interfaces.rst:284-292`; "the translation of
do-notation is entirely syntactic", 324), and a local definition in a do
block is "defined in the scope of" the names before it, which "will also
be in scope when declaring the *type* of the local definition"
(`docs/source/updates/updates.rst:514-531`, 549-551). The parser builds
a do block's `let` and a `let ... in` from one function
(`letFactory`, `src/Idris/Parser/Let.idr:34`, called by `mkLets`, 56, and
`mkDoLets`, 72).

## Cause

*read* at 89ba32eb. The desugarer carries `ps`, the names bound around a
term, which a declaration's type must not bind as implicits
(`desugarType` passes them to `bindTypeNames`, which binds every other
unapplied lowercase name). A lambda and a `let ... in` add the names they
bind before desugaring their scope, and a local block adds the names it
defines before desugaring its declarations and its scope
(`src/Idris/Desugar.idr`: `PLam` 342 and 350, `PLet` 364, `PLocal`
376-378). `expandDo` does so for a bind and a let of a pattern
(`DoBindPat` 773, `DoLetPat` 804) but not for a bind of a name (`DoBind`
765), a let of a name (`DoLet` 791) or a local block (`DoLetLocal`
812-814), whose declarations, too, are desugared under the `ps` from
before the block. So a type in a later local declaration binds those
names as implicits.

For a bound name the elaborator then declines the binding: in a type, a
name the environment already holds is checked as itself
(`checkBindVar`, `src/TTImp/Elab/ImplicitBind.idr:426-431`), and a
lambda or let binds it in the environment. What remains of that half is a
warning that is false, "We are about to implicitly bind the following
lowercase names ... size is shadowing Shadow.size", whenever the bound
name is also a global's (`Shadow.idr`; INT-17 saw it for `entered` in
`build`). A local definition is no variable of the environment (a
nested name, `localHelper`, `src/TTImp/Elab/Local.idr:51-53` and 85), so
its name is bound as an implicit, and the type means something else:
ambiguous, as above, or a fresh variable where it should be the
definition.

## Patch

`idris.patch`, against 89ba32eb (no other patch of the series touches
the file), changes `expandDo` in `src/Idris/Desugar.idr`: a bind of a
name and a let of a name add it to `ps` for the rest of the block, as
`PLam` and `PLet` do, and a local block adds the names it defines
(`definedIn`) for its own declarations and the rest of the block, as
`PLocal` does. A do block then desugars as its translation does.

Our type checker (compiler/checker), Idris's copied into our tree, has
the same `expandDo` (its `src/Idris/Desugar.idr`, `DoBind` 792, `DoLet`
818, `DoLetLocal` 840-841); its fix is its own code, as every fix there
is.

Nothing else changes: `ps` is read only to decide which names a type
binds as implicits. For a bound name the elaborator already checked the
name as itself, so only the false warning goes; `Bound.idr`, whose local
type names the do-bound `n`, is refused for the same mismatch as the
lambda form it translates to, before and after. For a local definition the
type now refers to it, as in `let ... in`; a program that meant a fresh
implicit by the name of a local definition of the block is written with
another name, as it must be outside a do block.

## Testing

On full bootstraps of 89ba32eb (scratch, Chez 10.4.1, 2026-10-23, this
repository's 8-core arm64 macOS machine), one with every Idris patch, 96
and 104 to 111, and one with this patch as well, each of which built
itself and all its libraries and ran the bootstrap's own targets, `make
bootstrap install install-api`, to the end, side by side: 485 s wall
each (bootstrap 340 s, install 4 s, install-api 141 s, alike), 2.9 GiB
peak RSS (rusage) each, with the same six warnings and no error
(*measured*). With the patch, Idris's own source, which `install-api`
checks, and its libraries check as before.

- `Local.idr` checks; without the patch each of its three definitions is
  refused as above. INT-17's `repro/LocalType.idr` and `LocalType3.idr`
  check; `LocalType2.idr` (let-in) and `LocalType4.idr` check, as before.
- `Bound.idr` is refused, its two definitions for `Mismatch between: S
  ?len and n`, with the patch and without it.
- `Shadow.idr` checks with no warning; without the patch it checks with
  two (`size`, do-bound, and `width`, let-bound).
- upstream's own tests, in the 31 groups 108's README lists, run by
  upstream's runner as `make retest` runs it in the built tree: 731 of
  733 pass with the patch and without it, the same two failing,
  `casetree/heuristics001` (105's) and `literate/literate006` (108's),
  and every test's result is the same, as in 111's runs.
- INT-17's `repro/IfWhere.idr` is refused as before (each `if` is a case
  function of its own, the language's behaviour, not this bug), and 111's
  reproducers give 111's results.

`tests/upstream-do-local-definition-scope` checks that the pinned Idris
accepts `Local.idr`, refuses `Bound.idr` for its mismatch, and checks
`Shadow.idr` without a warning of an implicit binding. Its run script,
run directly against each scratch build (`IDRIS_MLIR_TOOLCHAIN` naming a
directory whose `idris2` is that build's prefix), prints its expected
output with the patch, and without it the `Local` and `Shadow` lines
that say the bug still reproduces.

## When it goes

When the Idris pin carries an upstream fix (the check then passes without
the patch; upstream main has the same `expandDo` on 2026-10-23), or when
nothing of ours meets the shape. Until then the bootstrap applies the
patch.

Our type checker (compiler/checker) now carries the change as its own code,
in `Idris.Desugar.expandDo`, which `tests/checker-do-local-definition-scope`
checks; it stays when the patch goes.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in their own words, is their call. The patch goes when the pin moves
past upstream's fix, which `tests/upstream-do-local-definition-scope`
shows by passing on an unpatched pin.
