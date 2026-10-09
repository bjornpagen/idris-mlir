# [Idris2] Elaboration replaces a primitive applied to constants with the compiler's own result

At the pin (third_party/Idris2 at 1c630e67), a definition whose right-hand
side applies a primitive to constants is checked to the constant Idris's
own evaluator computes: `plain = prim__cast_StringInt "12.7"` is stored as
`plain = 12`. The evaluator's primitives are Idris's implementations, run
on the Scheme that runs Idris, so the checked term holds Chez's meaning of
the primitive, and a backend whose primitive means something else never
sees the call. The same happens to a literal whose conversion
(`fromString`, `fromInteger`, `fromDouble`, `fromChar`) applies a
primitive: with `fromString s = MkN (prim__cast_StringInt s)`, the literal
`"12.7" : N` is checked to `MkN 12`.

Every backend is affected where its primitive differs from the
evaluator's. RefC writes a Double with `printf("%f")` and reads a String
with `atoi` (`support/refc/casts.c`); Node writes `Infinity`
(`jsAnyToString`, `src/Compiler/ES/Codegen.idr:472`). The same program
then prints the evaluator's text when the argument is a literal and the
backend's when it is a variable. For this compiler, whose runtime is the
one meaning of every primitive (`findings/decision-primitive-semantics.md`),
these constants came out as Chez's values:

| right-hand side | checked to | the runtime |
| --- | --- | --- |
| `prim__cast_DoubleString (prim__div_Double 1.0 0.0)` | `"+inf.0"` | `inf` |
| `prim__cast_DoubleString 4.9e-324` | `"5e-324\|1"` | `5e-324` |
| `prim__cast_DoubleString 12.886856079101562` | `"12.886856079101563"` | `12.886856079101562` |
| `prim__cast_StringInt "12.7"` | `12` | `0` |
| `prim__cast_CharString '\233'` | `"\\233"`, four characters | `é` |

The last line is a second bug of the evaluator, which the change leaves
alone: `castString` of a Char is `stripQuotes (show c)`
(`src/Core/Primitives.idr:42`), the escape `show` writes, not the
character.

## Reproduce

`Fold.idr`, with the toolchain's (unpatched) Idris:

```
$ printf ':printdef plain\n:printdef infinity\n:printdef eAcute\n:printdef viaLiteral\n:q\n' | idris2 --no-banner Fold.idr
1/1: Building Fold (Fold.idr)
Main> Main.plain : Int
plain = 12
...
```

`:di plain` prints `Compile time tree: 12`, and `--log declare.def:10`
shows where it happens: `Checking RHS (prim__cast_StringInt (fromString
"12.7"))`, then `RHS term: 12`. `--log elab:10` shows the elaborator itself
producing `(prim__cast_StringInt "12.7")`; the constant appears after it.
Observed on arm64 macOS: `plain` and `infinity` are `12` and `"+inf.0"` in
the compile-time tree, `viaLiteral` is `MkN 12`, and a `FromDouble String`
whose `fromDouble` is `prim__cast_DoubleString` checks
`12.886856079101562` to `"12.886856079101563"`.
`tests/upstream/elaboration-primitive-folding` checks the reproducer.

`infinity` must be `partial`: `prim__div_Double` is not covering. At the
pin the fold removes the call before the coverage check, so the same
definition without `partial` is accepted; with the change it is not, as
the same division of a variable is not.

## Expected

The checked definition keeps the call, `plain = prim__cast_StringInt
"12.7"`, as it keeps a call of any function, and the backend computes it.
A literal of a primitive type is still the constant it denotes (`small =
42`).

## Cause

- `elabTermSub` (`src/TTImp/Elab.idr:150-155`) normalises every checked
  term with `normaliseArgHoles` (or `normaliseHoles`), which evaluate with
  `withArgHoles` (`withHoles`): modes meant to fill in solved holes and
  nothing else.
- In those modes the evaluator leaves a definition applied
  (`evalDef ... (PMDef ...)`, `src/Core/Normalise/Eval.idr:505-532`, the
  condition at `:515`), and a `let` (`:125`, `:175`), but its case for a
  primitive, `evalDef ... (Builtin op)` (`:548-549`), reduces in every
  mode: `evalOp (getOp op)`.
- So a primitive whose arguments are constants is replaced by
  `getOp`'s result (`src/Core/Primitives.idr`), and the clause stored is
  that constant (`src/TTImp/ProcessDef.idr:427` logs it).
- Separately, `normalisePrims` (`src/Core/Normalise.idr:334-347`, called
  from `checkApp`, `src/TTImp/Elab/App.idr:839`, and from `mkPat`,
  `src/Core/Case/CaseBuilder.idr:1000`) reduces a literal's conversion to a
  constant with `normalise` or `normaliseAll`, which run every primitive
  the conversion reaches, including those of a user's implementation.

## The fix

`pull-request.diff`, against the pin, is the pull request:

- `evalDef` reduces a primitive under the condition the evaluator already
  applies to `let`: not in `holesOnly` or `argHolesOnly` mode, unless
  `tcInline` (the totality checker's `tcOnly`) is set. Elaboration's
  normalisation then leaves a primitive applied, as it leaves a function.
  `nf`, `normalise` and `normaliseAll` reduce primitives as before, so
  type checking, conversion and the REPL's evaluation are unchanged.
- The exception is `believe_me` (`coercionOp`, `Core.Primitives`), which
  computes nothing: it is its argument on every backend. Those modes still
  reduce it, as they did. A `Fin` literal whose bound is not known when it
  is elaborated (`index 1 v`) keeps base's conversion applied, with the
  proof of the bound forged by `believe_me` from an auto-implicit hole
  (`Data.Fin.fromInteger`'s `lemma`); where the hole is solved by the
  elaborator's last normalisation, that turns `believe_me Oh` into `Oh`.
  Left applied, the escape hatch would stay in the checked term of every
  such literal.
- `EvalOpts` gets `sharedPrimsOnly`, False in every named set of options.
  With it, a primitive reduces only through `sharedOp`
  (`Core.Primitives`), which computes Integer's arithmetic and
  comparisons, a cast from Integer to a fixed-width integer, and a cast
  from Integer to Double when it is exact (|x| ≤ 2^53). Those mean the
  same on every backend: Integer is unbounded, its division and remainder
  are Euclidean on every backend (upstream's `integers` tests), and the
  casts wrap or are exact, and `believe_me`. Every other primitive stays
  applied.
- `normalisePrims` evaluates with `sharedPrimsOnly`. The Prelude's and
  base's conversions use only those primitives (`prim__cast_Integer<T>`,
  `integerToNat`'s `prim__lte_Integer` and `prim__sub_Integer`, `Fin`'s
  `restrict`), so their literals are constants as before. A user's
  conversion keeps any other primitive applied: `"12.7" : N` is checked to
  `MkN (prim__cast_StringInt "12.7")`.
- On a left-hand side (`all`, also `mkPat`'s call), `normalisePrims`
  normalises fully as well, and when the two results differ it reports
  that the literal can't be matched. Without that check the call left in
  the pattern would be `PUnmatchable`, which the case builder takes for a
  variable (`clauseType'`, `src/Core/Case/CaseBuilder.idr:336`), so the
  clause would match every value. Such a clause was accepted with Chez's
  value and is now refused; a literal pattern of a primitive type, `Nat`
  or `Fin` is unchanged. An Integer literal pattern of type Double beyond
  2^53 is refused too, since its rounding is the backend's.

Upstream test: `tests/idris2/evaluator/evaluator006` (in the diff),
`:printdef` of a primitive applied to constants, a literal through a
`FromString` with a primitive, and literals of `Int` and `Nat`.

## Why there is no patch

There is no `idris.patch`. The Idris that elaborates what this compiler
consumes, programs, prelude, base and contrib alike, is the fork of
Idris's compiler in compiler/idris, and the fork carries the change of
`pull-request.diff` to its `src/` as its own code (its README lists it;
PINS.md `idris-fork` and `elaboration-primitive-folding`). The stock Idris
the bootstrap builds only builds stage 0, the fork, the frontend and the
test runner, which do not depend on what elaboration folds, and the
benchmarks' Chez baseline, which runs on the Chez whose meaning the fold
computes, so it stays unpatched. The pull request is still one we intend to send, drafted as
`pull-request.diff`, which the bootstrap does not apply.

## Testing at the pin

`pull-request.diff` applies to the pin (`git -C third_party/Idris2 apply
--check`), and its `src/` part is the fork's change, byte for byte: applied
to the pin's four files it gives compiler/idris's. Upstream's own suite has
not run with it, nor has a stock Idris been built with it.

The fork, built with it by the stock Idris on arm64 macOS (2026-10-09),
built prelude, base, contrib and `libs/mlir-linear` without an error, so
no literal pattern in them needs a backend's primitive. Over this
repository's 702 test programs (the frontend's Core and MLIR, compiled
with the stub tools), against the same fork without the change: 525 are
byte-identical; in the other 177 compilations (90 programs, each with and
without compile-time evaluation where the suite does both) every
difference is a constant that is now the primitive call written in the
source (`12:Int` is `cast_StringInt("12.7")`, `"+inf.0"` is
`cast_DoubleString(div_Double(1.0, 0.0))`, `3:Int` is `add_Int(1, 2)`),
and no exit status or message changed. Without the `believe_me`
exception, `tests/programs/data/vect` was refused (`unsupported (escape
hatch): believe_me`), its `index 1 v` keeping the forged proof.
`tests/upstream/elaboration-primitive-folding` checks the reproducer
through the frontend.

## What it changes here

With the change, the program this compiler consumes keeps every primitive
call the user wrote, and the runtime computes it, at compile time or at
run time. The test generators no longer hide literals behind an identity
(`tests/Sem.idr`'s `litInt`, the `lit<T>` of `tests/TwoLevels.idr` and
`tests/Fuzz.idr`): a primitive applied to literals is what they test. The
fixtures `tests/programs/semantics/closed-*` hold each example to the
runtime's documented meaning.

## Upstreaming plan

Status: not filed; carried as the fork's code, not yet run through
upstream's suite.

- Where: an issue on idris-lang/Idris2 (the reproducer, with RefC's
  `0.100000` against the checked `"0.1"` for `prim__cast_DoubleString 0.1`,
  and Node's `Infinity` against `"+inf.0"`), and a pull request against
  `main`, one commit, `pull-request.diff`, with a CHANGELOG_NEXT.md
  entry.
  Before filing: search the tracker for elaboration constant folding and
  `normaliseArgHoles`; build the change on then-current `main` and run its
  suite, updating the expected files whose printed definitions keep their
  calls, and say which in the pull request.
- The change review may question: a left-hand-side literal whose
  conversion needs a backend-dependent primitive is refused. The
  alternative, keeping `normaliseAll` on the left, accepts a pattern whose
  value is the host's; the pull request names both.
- Separately, an issue for `castString` of a Char (`show`'s escape for
  a non-ASCII character), which the REPL's evaluation still shows.
- The fork's change goes when a re-sync of compiler/idris brings
  upstream's fix (compiler/idris/README.md); then this directory, its
  check and its `PINS.md` entry go.
