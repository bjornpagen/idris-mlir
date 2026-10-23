<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] A case reads its scrutinee's type before solving the constraints that fix it

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), the stock Idris,
unpatched and with the toolchain's series (96 and 104 to 116), refuses
`Bind.idr` (*measured*, scratch builds on Chez 10.4.1):

```
Error: While processing right hand side of seed. Can't infer type for case scrutinee
```

```idris
seed : Maybe String -> Integer
seed given =
  case given >>= parseInteger of
    Just s => s
    Nothing => 0
```

The scrutinee's type is `Maybe Integer`, fixed by the program: `given` is
a `Maybe String`, so the bind is `Maybe`'s, and the alternatives fix the
result. The same definition with the argument eta-expanded, `given >>=
(\s => parseInteger s)`, checks on the same builds, and nothing about
`parseInteger` matters: a monomorphic `parse : String -> Maybe Integer`
in its place is refused the same (`parsed`, in the same file). The
refusal is the elaborator's own stopgap ("For the moment, throw an error
if we haven't been able to work out the type of the case scrutinee",
`src/TTImp/Elab/Case.idr:409-411`), not a rule of the language ("Another
way of inspecting intermediate values is to use a ``case`` expression",
`docs/source/tutorial/typesfuns.rst:1343`). The test runner met it
twice (`harness/Determinism.idr:28`, `determinismSeed`, and
`harness/Universal.idr:136`, `actionsSeed`, each `case given >>=
parseInteger of` on an environment variable).

## Cause

*read* at 89ba32eb, and *measured* with the elaborator's logs (`--log
elab:10 --log unify:10`) on a scratch build of the pin.

- Checking `given` against `?m ?a` (the bind's first argument) meets
  `Maybe String =?= ?m ?a`. A metavariable applied to another
  metavariable is outside the pattern fragment, and `unifyHole` takes
  such an application apart (`unifyHoleApp`, solving `?a` and then `?m`)
  only when the hole is invertible (`src/Core/Unify.idr:851-860`);
  otherwise it postpones the constraint ("Not in pattern fragment",
  770-785). The function's argument, checked against `?a -> ?m ?b`,
  postpones `Maybe Integer =?= ?m ?b` the same way, and the application's
  result `?m ?b =?= Maybe ?_` (the type `guessScrType` reads off `Just`)
  too.
- A hole becomes invertible when an interface search fails because the
  hole is one of its determining arguments (`retryGuess`,
  `DeterminingArg`, `setInvertible`, 1447-1452): here the search for the
  bind's `Monad ?m`, which was added when the bind's implicit arguments
  were, and is first tried when constraints are next solved
  (`solveConstraints`, 1514-1521). Then the postponed constraints solve
  (`?m` as `Maybe`, `?b` as `Integer`) and the search finds `Monad Maybe`.
- `checkCase` checks the scrutinee and reads its type at once
  (`src/TTImp/Elab/Case.idr:403-406`): `runDelays` around the check runs
  the delayed elaborators again, not the postponed constraints. The type
  is still `?m ?b`, and `checkConcrete` refuses it (412-415). The
  eta-expanded argument checks because `checkLambda` solves the
  postponed constraints before it checks a lambda against its expected
  type (`src/TTImp/Elab/Binders.idr:171`), which here is before the case
  reads anything.

## Patch

`idris.patch`, against 89ba32eb with 96 and 104 to 116 (107 and 108
change the lines around it), changes `checkCase` alone: where the
scrutinee's type, normalised, is still headed by a metavariable, it
solves the postponed constraints (`solveConstraints`, `Normal`: no
default is applied) and normalises the type again before
`checkConcrete` decides. A case whose scrutinee's type is known when it
is read is elaborated as before, with nothing more solved. One whose type
was not, which the unpatched Idris refused there (to try again later
where the case was delayed, `delayElab`), has the constraints solved then
that solving would have met later anyway, in the same mode; one whose
type only a default fixes (`Literal.idr`, `case 3 of`) is still refused,
since `Normal` applies none.

Our type checker (compiler/checker), Idris's copied into our tree, has
the same code (`checkCaseDelayed`, its `src/TTImp/Elab/Case.idr:653-656`,
and the same `checkConcrete`, 662-665), so the same programs are refused
there; its fix is its own code, as every fix there is.

## Testing

On full bootstraps of 89ba32eb (scratch, Chez 10.4.1, 2026-10-23, this
repository's 8-core arm64 macOS machine at load average 12 to 41 from
other work), one with the series 96 and 104 to 116 and one with this
patch as well, each of which built itself and all its libraries and ran
`make bootstrap install install-api` to the end (*measured*, rusage):

| build | bootstrap | install-api |
| --- | --- | --- |
| the series | 567 s wall, 468 s user, 3.0 GiB | 283 s wall, 205 s user, 447 MiB; again: 199 s, 184 s, 694 MiB |
| with this patch | 889 s wall, 497 s user, 3.0 GiB | 319 s wall, 220 s user, 590 MiB; again: 201 s, 188 s, 693 MiB |

`install-api`, which checks Idris's own source with the built compiler,
gives the same three warnings of unreachable clauses and no error on
both, each run. The builds ran beside each other and other work, so the
walls differ by load; the peaks differ as much between two runs of one
build as between the builds.

- `Bind.idr` checks; on the unpatched pin (a scratch bootstrap of the
  gitlink) and on the series both its definitions are refused as above,
  and with the bind's argument eta-expanded both check there.
- `Literal.idr` is refused with the patch as on the pin and the series.
- every `tests/upstream-*` of an Idris patch (96 and 104 to 116, and
  this one's), run against the patched build, prints its expected
  output.
- upstream's own tests, in the 31 groups 108's README lists, run by
  upstream's runner as `make retest` runs it in each built tree (its
  failures file listing the groups; four threads): 731 of 733 pass with
  the patch and without it, and every test's result is the same; the two
  failing are `casetree/heuristics001` (105's) and
  `literate/literate006` (108's), as 116's README reports.
- the test runner: `harness/` and `compiler/spec` of the checkout at
  67cbb873 (the runner's text is d76f1b33's, which L19v left), exported
  and built as `make spec runner` builds them, with no edit: on the
  series it stops at `Determinism.idr` (module 9 of 31, this bug); with
  this patch it builds `Determinism` and `Universal` and stops at
  `Verdict.idr` (module 30 of 31, 118's bug); with 118 as well every
  module and the executable build (118's README).

`tests/upstream-case-scrutinee-postponed-constraints` checks that the
pinned Idris accepts `Bind.idr` and refuses `Literal.idr` for its
scrutinee's type. Its run script, run directly against each scratch build
(`IDRIS_MLIR_TOOLCHAIN` naming a directory whose `idris2` is that build's
prefix), prints its expected output with the patch, and without it, on
the unpatched pin and on the series, the `Bind` line that says the bug
still reproduces.

## When it goes

When the Idris pin carries an upstream fix (the check then passes without
the patch; upstream main has the same `checkCase` on 2026-10-23), or when
nothing of ours meets the shape. Until then the bootstrap applies the
patch.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in their own words, is their call. The patch goes when the pin
moves past upstream's fix, which
`tests/upstream-case-scrutinee-postponed-constraints` shows by passing on
an unpatched pin.
