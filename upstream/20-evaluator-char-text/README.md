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

`tests/idris2/evaluator/evaluator007/CharText.idr` in `pull-request.diff`,
with the toolchain's (unpatched) Idris: `idris2 --check CharText.idr`
refuses each of its four proofs with a mismatch between the Char and its
escape. Observed on arm64 macOS (2026-10-09) through the fork of Idris's
compiler before this change, whose `castString` is the pin's.
`tests/upstream/evaluator-char-text` checks the same four proofs through
the frontend.

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

`pull-request.diff`, against the pin, is the pull request: `castString` of
a Char is `prim__cast_CharString c`, the primitive itself, run by the
Scheme that runs Idris, as `strCons` and `strSubstr` already are; the
import of `Libraries.Utils.String`, used only for `stripQuotes`, goes.
Upstream test: `tests/idris2/evaluator/evaluator007` (in the diff), the
four proofs.

## Why there is no patch

There is no `idris.patch`. The Idris that elaborates what this compiler
consumes is the fork in compiler/idris, which carries the fix as its own
code: there every operation the evaluator computes calls the primitive of
its name (`Core.Primitives`; compiler/idris/README.md). The stock Idris
only builds stage 0 and the benchmarks' Chez baseline, which do not depend
on it, so it stays unpatched; the pull request is drafted as
`pull-request.diff`, which the bootstrap does not apply.

## Testing at the pin

`pull-request.diff` applies to the pin (`git -C third_party/Idris2 apply
--check`), alone and after 18's. No stock Idris has been built with it and
upstream's suite has not run with it. The fork, whose change computes the
same Char case with the same primitive, checks `CharText.idr` with the
output in the diff's `expected`, and refuses all four proofs without the
change (arm64 macOS, 2026-10-09).

## Upstreaming plan

Status: not filed; carried as the fork's code.

- Where: an issue on idris-lang/Idris2 (the `newline` proof above, refused,
  and its converse, accepted), and a pull request against `main`, one
  commit, `pull-request.diff`, with a CHANGELOG_NEXT.md entry. It is
  independent of 18 and smaller, so it may go first.
- Before filing: search the tracker for `stripQuotes`, `castString` and
  Char casts at compile time; build the change on then-current `main` and
  run its suite, `evaluator007` included.
- When it goes: when a re-sync of the fork brings upstream's fix; then this
  report, `tests/upstream/evaluator-char-text` and the PINS.md lines go.
