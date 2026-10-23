<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] A literal checked before its type is known is folded halfway, its conversion's body inlined into the caller

At the pin (third_party/Idris2 at 1c630e67, the toolchain's `idris2`
0.8.0-1c630e67c), elaboration folds a literal's conversion applied to a
constant (`fromInteger 2`) by normalising it (`normalisePrims`,
`src/TTImp/Elab/App.idr` and `src/Core/Normalise.idr`). Where the
literal's type still holds a hole, the normal form is stuck partway: for
a `Fin ?n`, base's `fromInteger` unfolds to `finFromInteger`, then to
`natToFinLT 2` with its bound's proof, which is the where block's erased
`lemma oh = believe_me oh` unfolded too. The caller's checked definition
then holds a `believe_me` it never wrote, and the call to `fromInteger`
it did write is gone.

## Reproduce

`Lit.idr` (here), with the toolchain's Idris:

```
$ echo ':di Main.main' | idris2 --no-banner Lit.idr
Compile time tree: printLn (applyTo (\v => index (natToFinLT 2) v) [10, 20, 30])
Refers to: prim__believe_me, ...
```

The lambda is checked before the vector that fixes `n = 3`, so `2` is
elaborated at `Fin ?n`. Written as `printLn (index 2 [10, 20, 30])`, the
bound is known first and the literal folds to `FS (FS FZ)`, a value with
nothing of `fromInteger` left in it. Observed on arm64 macOS, 2026-10-19.

For this compiler the inlined proof is user code's: a `believe_me` the
user's definition holds is refused (a forged bound is one the compiler
trusts when it reads an array without a check), so
`withArray [<3] k (\a => LArray.freeze (LArray.write a [<2] 70))` was
refused as `unsupported (escape hatch): Main.main: believe_me`, while the
same index written as a top-level `Index [<3]` compiled.

## Expected

The program as written: `fromInteger 2`, or its value once the type is
known. A fold that does not reach a value has changed what the caller
refers to without computing anything.

## Cause

`normalisePrims` (`src/Core/Normalise.idr`) normalises the whole
application whenever its last argument is a constant within the size
heuristic, and keeps the result whatever it is. Normalisation unfolds
every definition the term applies, so a conversion that cannot finish
leaves its body, with the bodies of what it calls, in the caller.

## The fix

Our type checker (compiler/checker) has the change as its own code,
after 18's change to the same function. In an expression, the fold is kept
only when it reaches a value: a term
that applies no function (`appliesFunction` finds no reference to a
definition that is neither a constructor nor a type). Otherwise the call
stays as written, and is folded, or run, once its type is known. A
pattern (`all`) is unchanged: it must be the constant it matches.

The compiler's own part is separate: walking a trusted library, the
profile does not follow its definitions of quantity 0 (`proofOnly` in
compiler/src/IdrisMLIR/Frontend/Profile.idr), since those never run; a
user's are still walked.

An upstream test would hold `Lit.idr` and check that `:di Main.main`
refers to no `prim__believe_me`; none is drafted, since nothing is sent.

## Why there is no patch

There is no `idris.patch`: nothing the stock Idris builds meets the bug.
The Idris that elaborates what this compiler consumes is our type checker
in compiler/checker, Idris's checker copied into our tree, which has the
change as its own code. The stock Idris only builds stage 0 (the checker,
the frontend and the test runner) and the benchmarks' Chez baseline, and
nothing it builds needs a literal's call kept.

## Testing

`tests/upstream-literal-partial-fold` is refused (`unsupported (escape
hatch)`) through the unchanged checker, and prints 30 through the changed
one.

## Upstreaming plan

Status: recorded, not carried; nothing goes to idris-lang/Idris2 from
here. Idris accepts no contribution that arises from generative AI or a
coding agent, issues, pull requests, commits and comments alike
(upstream/README.md, **Idris**), and this report was written with one.
Whether to report the bug upstream is Bjorn's call alone, in their own
words and from their own understanding; nothing here is drafted for it.
The report goes when the Idris pin carries upstream's own fix; the
checker keeps its own, which `tests/upstream-literal-partial-fold` checks.
