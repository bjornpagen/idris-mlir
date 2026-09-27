# v2 entry experiment (RM-V2-1)

Results of probing the pinned Idris (1c630e67) and Chez Scheme 9.5.8 before
v2, as the roadmap asks. Each item states what was run and what it showed.

## Interfaces in checked TT

Probe: user-defined `Semi`/`Mon` (a superclass and a value method) and a
higher-kinded `Mnd m` with `ret`/`bind`, a `Loud` subclass with a default
method, implementations for a state record, and `do` over them. Inspected
with `:di` in the stock REPL and with our backend.

- An interface is a single-constructor data type whose parameters are the
  interface's parameters and whose fields are the superclass dictionaries,
  then the methods, in order. Implementations are ordinary `PMDef`s
  returning that constructor applied to lambdas.
- A method is a projection function, for example:

  ```
  M.bind   args [{arg:0}, {arg:1}, {arg:2}, {arg:3}]
  case {arg:3} : Mnd {arg:2} of
    Mnd {e:0} {e:1} {e:2} => {e:2} {arg:0} {arg:1}
  ```

  `{e:0}` is the parameter `m`; `{e:1}`, `{e:2}` are `ret` and `bind`. A
  method with its own type variables has a field of polymorphic type,
  `(0 a : Type) -> (0 b : Type) -> m a -> (a -> m b) -> m b`, and the
  projection applies the field to the type arguments it received.
- A default method is an ordinary field; the implementation fills it with
  the default's body.
- Superclass dictionaries are fields reached through projection functions
  named `Constraint (Semi a)`.
- `do` desugars to whatever `>>=` and `>>` are in scope. With
  `IdrisMLIR.IO` imported, a user module that defines its own `(>>=)` and
  `(>>)` over a user `Mnd` gets them by type-directed disambiguation. A
  statement without a binder uses `>>`, which must exist for the monad.

What our backend did (at 80d7059):
- A first-order interface (fields of value or function type, no method type
  variables) already works once a deferred dictionary's value fields are read
  at the match (fixed in 80d7059). Every dictionary is eliminated.
- A method field of polymorphic type is rejected: `coreType` of
  `(0 a : Type) -> a -> m a` substitutes `Erased` for `a` and then meets a
  runtime binder of type `Erased` (PROF-DATA-2).

Conclusion, after trying it: a *polymorphic value* type (a compile-time
type for method fields, instantiated at each use) is not enough. A method's
body mentions its own type variables (`ret x = MkSt (\s => (x, s))` builds
a `Pair a s`), so it can only be translated once those are known, and they
are known only where the method is used. Translating the method generically
fails the same way `coreType` did.

What works is to treat implementations as what they are in Idris: values
resolved at compile time, like type arguments (FE-TR-6). An auto-implicit
argument is a closed TT term that keys the instance; a match on it is
decided during translation by unfolding the implementation to its
constructor; a method applied to its type arguments is substituted with
them and then translated at those types. No dictionary reaches Core, and
`Simplify` is unchanged. One wrinkle: Idris passes an enclosing function's
constraints to its case and with blocks as explicit arguments, so an
argument that is a variable bound to an implementation is static whatever
binds it.

## Double on the reference backend

Chez 9.5.8 as installed (`/usr/bin/chezscheme`), with the Idris Chez code
generator (`Compiler/Scheme/Common.idr`, `support/chez/support.ss`).

Primitives:
- `+ - * /` and negation are flonum operations (`/` is `fl/`, negation is
  `-`); comparisons are `< <= = >= >`, false when an operand is NaN, and
  `0.0 = -0.0`.
- `exp log pow sin cos tan asin acos atan` are `flexp fllog flexpt flsin ...`,
  which call the C library: `nm -D /usr/bin/chezscheme` shows it imports
  `exp log pow sin cos tan asin acos atan sqrt` from libm (glibc).
- `sqrt floor ceiling` are exact IEEE operations.
- Int → Double is `exact->inexact`: round to nearest, ties to even.
- Double → Int of width w is `exact-truncate` then wrapping to w bits
  (`blodwen-toSignedInt`/`toUnsignedInt`). `(exact (truncate +nan.0))`
  raises "no exact representation for +nan.0"; so do the infinities.
- Double → String is `number->string`; String → Double is `string->number`
  (compile time only here).

`number->string` on flonums (probed on 60 values):
- Shortest digits that read back as the same double.
- Positional notation exactly when 1e-3 ≤ |x| < 1e10: `100.0`, `0.001`,
  `1234567890.0`, `1.5`, `0.0025`; an integer value keeps `.0`.
- Otherwise scientific, digits with a point only when there is more than one
  digit, `e`, and the exponent without `+`: `1e10`, `1.5e10`, `1e-4`,
  `1.2345678901e10`, `1.2345678901234568e20`, `9.313225746154785e-10`.
- `-0.0`, `+nan.0`, `+inf.0`, `-inf.0`.
- Subnormals end with `|p`, the precision in bits: `5e-324|1`.

Consequences for v2:
- Transcendental functions must call the same libm to agree with Chez bit
  for bit; they do not allocate, so linking them keeps programs heap-free.
- Printing a Double needs a shortest round-trip algorithm (Ryu, Adams PLDI
  2018) and these layout rules. At compile time the compiler itself runs on
  the same Chez, so folding `show` of a literal is exact by construction.
