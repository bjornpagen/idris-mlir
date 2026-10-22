<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] The evaluator computes a Char's text as its escape

At the pin (third_party/Idris2 at 1c630e67), the evaluator's
`prim__cast_CharString` of a constant Char is the escape `show` writes for
it, without the quotes, not the Char: `castString` of a `Ch` is
`stripQuotes (show c)` (`src/Core/Primitives.idr:42`). For a printable
ASCII Char the two agree; for any other they do not. `cast '\n'` is
`"\\n"`, two characters, where the Chez backend's `prim__cast_CharString`
gives the newline; `cast '\233'` is `"\\233"`, four, where a backend
gives `é`; and `'\\'` and `'\''` come out escaped too.

Where the evaluator runs, the type checker sees the escape. A proof that
holds of the primitive is refused:

```idris
newline : cast '\n' = "\n"
newline = Refl
```

```
Error: While processing right hand side of newline. When unifying:
    fromString "\n" = fromString "\n"
and:
    prim__cast_CharString '\n' = fromString "\n"
Mismatch between: "\n" and "\\n".
```

and one that does not (`cast '\n' = "\\n"`) is accepted. Before
upstream/18's change, elaboration also stored the escape in the checked
term of any definition that applies the cast to a constant (18's
`eAcute`); with it, the call stays there, and the bug is left in
conversion checking, as above.

## Reproduce

The proofs of `tests/upstream-evaluator-char-text/Main.idr`, with the
toolchain's (unpatched) Idris: `idris2 --check` refuses each with a
mismatch between the Char and its escape. Observed on arm64 macOS
(2026-10-09) through our type checker before this change, whose
`castString` was the pin's. `tests/upstream-evaluator-char-text` checks
the same proofs through the frontend.

## Expected

The four proofs check: the text of a Char is the one-character string of
that Char, which is what the Chez backend's `prim__cast_CharString`
computes (`string`, `src/Compiler/Scheme/Common.idr:191`). The
converse, `cast '\n' = "\\n"`, which the pin accepts, is refused.

## Cause

`castString`'s case for a Char reuses `Show Char`, which writes an Idris
character literal (`showLitChar`, `libs/prelude/Prelude/Show.idr:153`),
and strips the quotes, but keeps the escape inside them.

## The fix

The one-line fix: `castString` of a Char is `prim__cast_CharString c`,
the primitive itself, run by the Scheme that runs Idris, as `strCons` and
`strSubstr` already are. Our type checker (compiler/checker) goes further,
as its own code: every operation the evaluator computes calls the
primitive of its name (`Core.Primitives`; compiler/checker/README.md).

## Why there is no patch

There is no `idris.patch`: nothing the stock Idris builds meets the bug.
The Idris that elaborates what this compiler consumes is our type checker
in compiler/checker, Idris's checker copied into our tree, which has the
fix as its own code. The stock Idris only builds stage 0 and the
benchmarks' Chez baseline, which do not depend on it, so it stays
unpatched.

## Testing

The checker, whose change computes the same Char case with the same
primitive, checked the four proofs of this report's first reproducer, and
refused all four without the change (arm64 macOS, 2026-10-09).

## Upstreaming plan

Status: recorded, not carried; nothing goes to idris-lang/Idris2 from
here. Idris accepts no contribution that arises from generative AI or a
coding agent, issues, pull requests, commits and comments alike
(upstream/README.md, **Idris**), and this report was written with one.
Whether to report the bug upstream is Bjorn's call alone, in his own
words and from his own understanding; nothing here is drafted for it.
The report goes when the Idris pin carries upstream's own fix; the
checker keeps its own, which `tests/upstream-evaluator-char-text` checks.
