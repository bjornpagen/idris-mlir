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

The last line is a second bug of the evaluator, which the patch does not
change: `castString` of a Char is `stripQuotes (show c)`
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
definition without `partial` is accepted; with the patch it is not, as
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

## Patch

`idris.patch`, against the pin, is the pull request:

- `evalDef` reduces a primitive under the condition the evaluator already
  applies to `let`: not in `holesOnly` or `argHolesOnly` mode, unless
  `tcInline` (the totality checker's `tcOnly`) is set. Elaboration's
  normalisation then leaves a primitive applied, as it leaves a function.
  `nf`, `normalise` and `normaliseAll` reduce primitives as before, so
  type checking, conversion and the REPL's evaluation are unchanged.
- `EvalOpts` gets `sharedPrimsOnly`, False in every named set of options.
  With it, a primitive reduces only through `sharedOp`
  (`Core.Primitives`), which computes Integer's arithmetic and
  comparisons, a cast from Integer to a fixed-width integer, and a cast
  from Integer to Double when it is exact (|x| ≤ 2^53). Those mean the
  same on every backend: Integer is unbounded, its division and remainder
  are Euclidean on every backend (upstream's `integers` tests), and the
  casts wrap or are exact. Every other primitive stays applied.
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

Upstream test: `tests/idris2/evaluator/evaluator006` (in the patch),
`:printdef` of a primitive applied to constants, a literal through a
`FromString` with a primitive, and literals of `Int` and `Nat`.

## Testing at the pin

Not yet built. The patch applies to the pin
(`git -C third_party/Idris2 apply --check`, and
`tests/spec/upstream-patches`). Neither the patched Idris, its own test
suite, nor this repository's tests have run with it. Before it is relied
on:

- `tools/bootstrap.sh idris` builds Idris and its libraries with the
  patch (the libraries are built by the patched compiler, so the
  installed prelude and base hold the unfolded calls);
- `make test-mlir-tools only=elaboration-primitive-folding` runs the
  check; `make check`, `make build`, `make test`;
- upstream's suite (`make test` in a copy of third_party/Idris2 with the
  patch): its expected files that print a definition folded by elaboration
  will change, and `evaluator006`'s expected file was written by hand from
  how the unpatched compiler prints the same forms.

## What it changes here

With the patch, the program this compiler consumes keeps every primitive
call the user wrote, and the runtime computes it, at compile time or at
run time. The test generators no longer hide literals behind an identity
(`tests/Sem.idr`'s `litInt`, the `lit<T>` of `tests/TwoLevels.idr` and
`tests/Fuzz.idr`): a primitive applied to literals is what they test. The
fixtures `tests/programs/semantics/closed-*` hold each example to the
runtime's documented meaning.

## Upstreaming plan

Status: not filed; the patch has not been built.

- Where: an issue on idris-lang/Idris2 (the reproducer, with RefC's
  `0.100000` against the checked `"0.1"` for `prim__cast_DoubleString 0.1`,
  and Node's `Infinity` against `"+inf.0"`), and a pull request against
  `main`, one commit, `idris.patch`, with a CHANGELOG_NEXT.md entry.
  Before filing: search the tracker for elaboration constant folding and
  `normaliseArgHoles`; build the patch on then-current `main` and run its
  suite, updating the expected files whose printed definitions keep their
  calls, and say which in the pull request.
- The change review may question: a left-hand-side literal whose
  conversion needs a backend-dependent primitive is refused. The
  alternative, keeping `normaliseAll` on the left, accepts a pattern whose
  value is the host's; the pull request names both.
- Separately, an issue for `castString` of a Char (`show`'s escape for
  a non-ASCII character), which the REPL's evaluation still shows.
- The patch is dropped when the pin includes the fix; then this
  directory, its check and its `PINS.md` entry go.
