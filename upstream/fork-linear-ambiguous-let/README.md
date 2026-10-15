<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] A linear `let` whose value names an ambiguous function is refused

At the pin (third_party/Idris2 at 1c630e67), a `let` whose value uses a
linear variable is refused when the function applied has more than one
candidate in scope, although exactly one candidate fits. With
`Array.Core.shape` and `Array.Core.LArray.shape` both visible, `let e # a =
shape a in ...` over a linear `a` fails; written `LArray.shape a`, it is
accepted.

## Reproduce

`LinearLet.idr`, here and as the upstream test in `pull-request.diff`
(`tests/idris2/linear/linear021`): a linear `Handle`, two functions named
`size` (one of a `List`, one of a linear `Handle` returning the size and the
handle as a `Res`), and two definitions that apply the unqualified `size` to
the linear handle, one on the right of a pattern `let` and one on the right
of a plain `let`. With the toolchain's (unpatched) Idris, `idris2 --check
LinearLet.idr` reports for both:

```
Error: While processing right hand side of twice. Sorry, I can't find any
elaboration which works. All errors:
If LinearLet.Linear.size: Trying to use linear name h in non-linear context.
If LinearLet.Plain.size: Trying to use linear name h in non-linear context.
```

The same file with `Linear.size` checks (arm64 macOS, 2026-10-15).

## Expected

Both definitions check, as they do when the name is written qualified: the
value is checked at multiplicity one, where `Linear.size` fits and
`Plain.size` does not.

## Cause

A `let` checks its value at the multiplicity of its context, and checks it
again at one when the first attempt failed because a linear variable was
used at another multiplicity. A pattern `let` is a case block, whose
scrutinee is checked the same way (`checkCase`,
`src/TTImp/Elab/Case.idr:390-401`); a plain `let` is `checkLet`
(`src/TTImp/Elab/Binders.idr:249-268`). Each recognises the failure by its
own test of the error: `checkCase` matches a bare `LinearMisuse`, and
`checkLet`'s `linearErr` also looks through `InType`, `InCon`, `InLHS` and
`InRHS`.

An ambiguous name is elaborated by trying every candidate
(`exactlyOne'`, `src/TTImp/Elab/Check.idr`); when all fail, the error is
`AllFailed`, the list of each candidate's error. At the context's
multiplicity both candidates fail by using `h` non-linearly, so the error
is `AllFailed [LinearMisuse ..., LinearMisuse ...]`, which neither test
recognises, and the value is never checked at one.

## The fix

`pull-request.diff`, against the pin, is the change:

- `misusesLinear` (`src/TTImp/Elab/Delayed.idr`, beside `ambiguous` and
  `recoverable`, the other tests of what a failed elaboration means) is the
  one test: a `LinearMisuse` of a linear binder, seen through `InType`,
  `InCon`, `InLHS` and `InRHS`, or an `AllFailed` any of whose candidates'
  errors is one. Checking again at one tries every candidate again, and
  only those that fit there succeed.
- `checkCase` and `checkLet` both ask it; `linearErr` is gone. `checkLet`'s
  branch for a misused binder that is not linear was the same as its branch
  for any other error (`rigMult` is the semiring's `|*|`), so it is one
  branch.

The retry checks the value at one only where the first attempt failed by a
misused linear binder, as before; it now also does when the misuse is one
candidate's among several.

## Why there is no patch

There is no `idris.patch`. The Idris that elaborates what this compiler
consumes is the fork in compiler/idris, which carries the change as its
own code (`TTImp.Elab.Delayed.misusesLinear`, asked by `checkCaseDelayed`
and `checkLet`); the stock Idris only builds stage 0 and the benchmarks'
Chez baseline, neither of which elaborates such a `let`.

## Testing at the pin

`pull-request.diff` applies to the pin (`git -C third_party/Idris2 apply
--check`). With it and the other `upstream/fork-*/pull-request.diff` applied in order to
a copy of the pin, the pinned compiler's 292 modules typecheck with the
toolchain's Idris (`idris2 --typecheck idris2api.ipkg`, arm64 macOS,
2026-10-15). No stock Idris has been built with it and upstream's suite has
not run with it. The fork with the change typechecks with the toolchain's
Idris; the reproducer has not been run through the fork, since nothing is
built on the machine the change was written on.

## Upstreaming plan

Status: carried as the fork's code; nothing goes to idris-lang/Idris2
from here. Idris accepts no contribution that arises from generative AI
or a coding agent, issues, pull requests, commits and comments alike
(upstream/README.md, **Idris**), and this report, the diff and the fork's
change were written with one.

- `pull-request.diff` is the record of what the fork changed against the
  pin, laid out as a stock checkout with the upstream test (`linear021`)
  it would carry. At a re-sync of compiler/idris (compiler/idris/README.md)
  it says what to look for upstream: if upstream has fixed the bug its own
  way, the fork takes upstream's code and drops this change; if not, the
  change is carried forward onto the new base.
- When upstream's fix arrives: this directory and the PINS.md entry go,
  and the qualified `LArray.shape` calls in libs/mlir-array may be written
  unqualified.
- Whether to report the bug upstream is Bjorn's call alone, in his own
  words and from his own understanding; nothing here is drafted for it.
