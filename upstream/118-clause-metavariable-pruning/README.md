<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] A case's type is not found from a clause that holds a metavariable of its own

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), the stock Idris,
unpatched and with the toolchain's series (96 and 104 to 117), refuses
`Tuple.idr` and `Scrutinee.idr` (*measured*, scratch builds on Chez
10.4.1):

```
Error: While processing right hand side of render. Can't infer type for case scrutinee
```

```idris
data Edit = Keep String | Delete String | Insert String

render : Edit -> String
render e =
  let (mark, l) = case e of
                    Keep x => (" ", x)
                    Delete x => ("-", x)
                    Insert x => ("+", x)
  in mark ++ l
```

The let's pattern is a pair, so the inner case is the outer case's
scrutinee, and its type is found from its clauses: each builds a pair of
a string literal and a `String`. The literal's type is `fromString`'s
`ty`, a metavariable that the let's body fixes (`mark ++ l`) or, failing
that, `FromString`'s `%defaulthint`. Nothing is left to the program: with
the literal's type given (`the String " "`) the series checks it, and an
outer case on the pair's constructor, `MkPair mark l`, whose type
`guessScrType` reads, checks unpatched. The language gives `case` blocks
inference ("Having better inference means that ``case`` blocks work more
effectively in Idris 2", `docs/source/updates/updates.rst:758-760`), and
the refusal is the elaborator's stopgap (117's README). `Scrutinee.idr`
is the same on a case of an expression (`case id e of`), which splits no
variable. The test runner met the shape in `harness/Verdict.idr:198`
(`editLines`).

## Cause

*read* at 89ba32eb, and *measured* with the elaborator's logs (`--log
elab:10 --log unify:10`) on scratch builds of the pin and of the series.

- The outer case's pattern, `(mark, l)`, is an alternative between
  `Pair` and `MkPair` (`src/Idris/Desugar.idr:526-531`), so
  `guessScrType` reads no type off it (`src/TTImp/Elab/Case.idr:438-450`)
  and the inner case is checked against a fresh metavariable, which it
  takes as the type of its clauses' results.
- Every metavariable is made applied to the whole environment it is made
  in (`newMetaLets`, `src/Core/UnifyState.idr:407-416`). The case's type
  stands over the variables outside the clauses: on a case of an
  expression, the environment; on a case that splits a variable, with
  108, the unsplit copy (unpatched, the split variable is replaced by each
  clause's pattern, outside the pattern fragment altogether: 108's
  family). The metavariables a clause makes, here `MkPair`'s implicit `a`
  that the literal's type becomes, stand over the clause's pattern
  variables as well.
- So the clause's constraint, `Pair ?a[s, x] String =?= ?caseTy[s]`, has
  a solution for `?caseTy` that mentions `?a` applied to `x`, which
  `?caseTy` cannot see; `unifyHole` finds the solution does not shrink to
  `?caseTy`'s variables and postpones it ("Can't shrink",
  `src/Core/Unify.idr:886-893`). It would shrink once `?a` were solved,
  but `?a` waits for the body or the default, and the default is applied
  only after every delayed elaborator has been retried for the last time
  (`src/TTImp/Elab.idr:126-144`): the outer case, delayed, gives up first
  ("Can't infer type for case scrutinee", `src/TTImp/Elab/Case.idr:412-415`).
- Yet `?a` cannot depend on `x` in any solution: `?caseTy` is solved over
  the variables outside the clause, `?a` stands in its solution applied
  as a pattern and not under another metavariable or a function that
  might drop it, and its type, `Type`, does not need `x`. Restricting it
  to the variables it can depend on (pruning) loses no solution, and the
  constraint is then solved at once: `?caseTy` as `Pair ?a' String`.

## Patch

`idris.patch`, against 89ba32eb (no other patch of the series touches the
file; it applies alone, and after 117 with the series), changes
`unifyHole` alone. Where a solution fails to shrink to the variables of
the metavariable being solved, even normalised, each unsolved
metavariable the elaborator made (not a hole the programmer named, nor
one that stands for an implicitly bound name) that stands in the solution
applied to distinct variables, some of which the solution may not
mention, and not inside the arguments of another metavariable or of a
function application, is solved as a fresh metavariable over the
variables it keeps, provided the variables it drops are a clause's
pattern variables and its type and the kept variables' types do not need
them; the solution, normalised again, is then shrunk and solved as
before, or postponed as before when it still does not shrink. Only in a
term (`InTerm`): a pattern's metavariables stand for its variables, and
nothing changes on a left-hand side, in a match or in a search.

Only a clause's pattern variables are dropped because pruning anywhere
else changed what the stock Idris's own library means (*measured*,
scratch builds). In a type, an unsolved metavariable made for an
implicit argument or a `_` is bound as one of the type's implicits at
the end (`bindUnsolved`, `src/TTImp/Elab/ImplicitBind.idr:116-157`,
registered at `src/TTImp/Elab/App.idr:188-189`), found by its name and
in the order its constraints left it. Pruned of the variables a type
binds (its own binders, or a lambda's in it), the specification's
`AllClosed` (`compiler/spec/IdrisMLIR/Spec/Families/Terms.idr:160-162`)
and base's `Control.Function` and `Data.These` were refused ("Unsolved
holes", the fresh ones); with `bindUnsolved` made to bind the fresh one
in the pruned one's place, base's `Data.Either.eitherMapFusion`, whose
argument types are `_`, was refused at its proof by `Refl` ("Can't solve
constraint between: f x and either (Delay f) (Delay g) (map p (Left
x))"). A type's own binders, and those of a lambda in it, are not
pattern variables, so the metavariables a type binds are pruned of none
of them (*read*); with the restriction, base and every library the
bootstrap builds build as before (**Testing**).

It changes nothing a unification solved before: pruning runs only where
`unifyHole` postponed. It solves what was postponed when its only
obstacle was such a metavariable; a constraint that needs the dropped
variable fails where it is met instead of waiting, as `Escape.idr` shows:
its clause builds `(n, xs)`, `xs : Vect n Nat` with `n` the clause's own,
and it is refused with the patch ("Can't solve constraint between: Vect n
Nat and ?b") as without it ("Can't infer type for case scrutinee").

On the unpatched pin `Tuple.idr` also needs 108 (its case splits `e`);
`Scrutinee.idr` needs this patch alone: the pin with this patch and no
other (an incremental scratch build of the pin's bootstrapped tree)
checks `Scrutinee.idr` and refuses `Tuple.idr` and `Escape.idr` as the
unpatched pin does (*measured*).

Our type checker (compiler/checker), Idris's copied into our tree, has
the same `unifyHole` (its `src/Core/Unify.idr:936-944`, "Can't shrink"),
so the same programs are refused there, and the same `bindUnsolved`
(`src/TTImp/Elab/ImplicitBind.idr:158-160`), which the restriction to a
clause's pattern variables keeps out of the way; its fix is its own code,
as every fix there is.

## Testing

On full bootstraps of 89ba32eb (scratch, Chez 10.4.1, 2026-10-23, this
repository's 8-core arm64 macOS machine at load average 12 to 51 from
other work), one with the series 96 and 104 to 117 and one with this
patch as well, each of which built itself and all its libraries and ran
`make bootstrap install install-api` to the end (*measured*, rusage):

| build | bootstrap | install-api |
| --- | --- | --- |
| 96 and 104 to 117 | 889 s wall, 497 s user, 3.0 GiB | 319 s wall, 220 s user, 590 MiB; again: 201 s, 188 s, 693 MiB |
| with this patch | 432 s wall, 405 s user, 3.0 GiB | 191 s wall, 179 s user, 599 MiB |

`install-api`, which checks Idris's own source with the built compiler,
gives the same three warnings of unreachable clauses and no error on
both. The walls differ by load (the first bootstrap ran beside two
others); `install-api`'s peak varies as much from run to run (the series
without 117: 447 MiB, then 694 MiB).

- `Tuple.idr` and `Scrutinee.idr` check; on the unpatched pin (a
  scratch bootstrap of the gitlink) and with 96 and 104 to 117 both are
  refused as above. `Escape.idr` is refused on all three.
- every `tests/upstream-*` of an Idris patch (96 and 104 to 117, and
  this one's), run against the patched build, prints its expected
  output.
- upstream's own tests, in the 31 groups 108's README lists, run by
  upstream's runner as `make retest` runs it in each built tree (its
  failures file listing the groups; four threads): 731 of 733 pass with
  the patch and without it, and every test's result is the same (and the
  same as with 96 and 104 to 116 alone); the two failing are
  `casetree/heuristics001` (105's) and `literate/literate006` (108's).
- the test runner: `harness/` and `compiler/spec` of the checkout at
  8be98ea3 (the runner's text is d76f1b33's), exported and built as `make
  spec runner` builds them, with no edit: on this build the
  specification's 86 modules, all 31 of the runner's and its executable
  build (143 s wall, 127 s user, 0.71 GiB), and the executable runs
  (`runtests --help`); exported at 67cbb873, it stops with 96 and 104 to
  117 at `Verdict.idr` (module 30 of 31, this bug), and with 96 and 104
  to 116 at `Determinism.idr` (module 9, 117's).

`tests/upstream-clause-metavariable-pruning` checks that the pinned Idris
accepts `Tuple.idr` and `Scrutinee.idr` and refuses `Escape.idr`. Its run
script, run directly against each scratch build (`IDRIS_MLIR_TOOLCHAIN`
naming a directory whose `idris2` is that build's prefix), prints its
expected output with the patch, and without it, on the unpatched pin and
on the series, the `Tuple` and `Scrutinee` lines that say the bug still
reproduces.

## When it goes

When the Idris pin carries an upstream fix (the check then passes without
the patch; upstream main has the same `unifyHole` on 2026-10-23), or when
nothing of ours meets the shape. Until then the bootstrap applies the
patch.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in their own words, is their call. The patch goes when the pin
moves past upstream's fix, which
`tests/upstream-clause-metavariable-pruning` shows by passing on an
unpatched pin.
