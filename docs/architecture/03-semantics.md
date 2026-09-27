# 03. Reference semantics

**Contract document.** Changes need the user's approval.

This document fixes what a profile program means. The compiler MUST preserve
this meaning. Every optimization, at every level, is bound by it.

## The reference

- **SEM-REF-1 (v0).** The meaning of a profile program is its meaning in the
  pinned Idris 2 (`third_party/Idris2`). Where Idris leaves behaviour to the
  backend, this document fixes it as follows:
  - **Values:** Idris's compile-time evaluator (`src/Core/Primitives.idr`,
    `src/Core/Normalise*`) is the reference. Every value it computes in a
    type (`Refl` proofs) MUST equal the compiled program's value.
  - **Runtime behaviour:** the Chez backend (`support/chez/support.ss`,
    `src/Compiler/Scheme/Common.idr`) is the reference for behaviour the
    evaluator does not define, such as crashes. Deviations are listed
    explicitly (`SEM-DEV-*`).
- **SEM-REF-2 (v0).** A primitive whose evaluator and Chez behaviour disagree,
  or whose Chez behaviour cannot be expressed in fixed-width machine
  arithmetic, stays out of the profile until this document specifies it
  (`SEM-EXCL-*`).
  - Check: review (a rule about what enters the profile)

## Evaluation

- **SEM-EVAL-1 (v0).** Evaluation is strict (call by value).
  - The arguments of a call, the fields of a constructor application, and the
    bound expression of a `let` are evaluated before the call, the
    construction, or the `let` body.
  - Only the selected alternative of a match is evaluated.
- **SEM-EVAL-2 (v0).** The order in which the arguments of one call are
  evaluated is unspecified.
  - Pure evaluation has one observable effect: a crash (`SEM-CRASH-1`).
    Every crash has the same exit status, so the order changes at most the
    message text.
  - IO effects are ordered by the world chain (`SEM-IO-1`), never by
    argument order.
  - The implementation evaluates left to right.
- **SEM-EVAL-3 (v0).** Quantity-0 arguments, fields and `let` bindings are
  never evaluated at runtime.
- **SEM-EVAL-4 (v0).** An evaluation that would crash MUST crash, even if its
  result is unused. No optimization may remove, reorder past an observable
  effect, or speculate an operation that may crash, unless it proves that the
  operation cannot crash (`OPT-SAFE-1`).
- **SEM-EVAL-5 (v0).** Non-termination is observable. No optimization may
  remove a computation that may not terminate, or assume that it terminates.
  In particular, the compiler MUST NOT emit LLVM attributes or metadata that
  assert termination or forward progress (`mustprogress`, `willreturn`)
  unless a later version of this document allows it.

*Note:* the Chez backend's own optimizations may drop unused `let` bindings.
Conformance tests therefore never rely on a crash in dead code; the rules
above bind this compiler regardless.

## Integers

`T` ranges over the v0 integer types. `w(T)` is the width: `Int` and `Int64`
are 64, `IntN` is N, `BitsN` is N. Signed types (`Int`, `IntN`) hold
`[-2^(w-1), 2^(w-1))`. Unsigned types (`BitsN`) hold `[0, 2^w)`.

- **SEM-INT-1 (v0).** `Int` is a 64-bit signed integer, identical in
  behaviour to `Int64`. This follows `intKind IntType = Signed (P 64)` in the
  pinned Idris.
- **SEM-INT-2 (v0). Wrapping.** Let `wrap_T(n)` be the unique value of `T`
  congruent to the mathematical integer `n` modulo `2^w(T)`. Then:
  - `add`, `sub` and `mul` compute `wrap_T` of the exact result;
  - there is no overflow trap and no undefined behaviour.

  This is the Chez behaviour of `bs+`, `bs-`, `bs*`, `bu+`, `bu-`, `bu*`.
- **SEM-INT-3 (v0). Division and modulus.** For `b ≠ 0`:
  - **Signed `div`** is Euclidean division, then `wrap_T`. Let `q = trunc(a/b)`
    and `r = a - b·q`. If `r < 0`, the quotient is `q - 1` when `b > 0` and
    `q + 1` when `b < 0`; otherwise it is `q`. The result is `wrap_T` of that
    quotient. So `MIN div -1 = MIN`.
  - **Signed `mod`** is the Euclidean remainder, always in `[0, |b|)`. With
    `r` as above: `r + b` if `r < 0` and `b > 0`; `r - b` if `r < 0` and
    `b < 0`; `r` otherwise. So `-7 mod 2 = 1` and `MIN mod -1 = 0`.
  - **Unsigned `div` and `mod`** are floor division and remainder.

  This is `blodwen-euclidDiv`, `blodwen-euclidMod`, `bs/` and `bu/` in
  `support.ss`. Examples: `-7 div 2 = -4`, `-7 div -2 = 4`, `7 div -2 = -3`,
  `-7 mod -2 = 1`.
- **SEM-INT-4 (v0). Division by zero.** `div` and `mod` with `b = 0` crash
  (`SEM-CRASH-1`). The evaluator treats them as stuck (`Nothing`), so no
  `Refl` proof can state a value for them.
- **SEM-INT-5 (v0). Bitwise.** `and`, `or` and `xor` operate on the `w(T)`-bit
  two's complement representation.
- **SEM-INT-6 (v0). Comparison.** `lt`, `lte`, `eq`, `gte` and `gt` compare
  the mathematical values: signed for signed types, unsigned for `BitsN`.
  The result is an `Int`: `1` if true and `0` if false (`boolop` in
  `Common.idr`).
- **SEM-INT-7 (v0). Casts.** `prim__cast_ST x` is `wrap_T` of the
  mathematical value of `x`. Consequences:
  - widening from a signed type sign-extends, and widening from an unsigned
    type zero-extends;
  - narrowing truncates.

  This is `intTo` in `Common.idr`, via `blodwen-toSignedInt` and
  `blodwen-toUnsignedInt`.
- **SEM-LIT-1 (v0).** An integer literal denotes the value that Idris stores
  in the elaborated TT constant for its type.

## Characters (v1)

- **SEM-CHAR-1 (v1).** A `Char` is a Unicode scalar value: `0..0xD7FF` or
  `0xE000..0x10FFFF`. A character literal denotes its scalar value.
- **SEM-CHAR-2 (v1).** `Char` comparisons compare scalar values. The result is
  an `Int`, `1` or `0`.
- **SEM-CHAR-3 (v1).** `prim__cast_CharT c` is `wrap_T` of `c`'s scalar value.
  `prim__cast_TChar x` is `x` if `x` is a scalar value, and `0` (`'\0'`)
  otherwise. This is `cast-char-boundedInt`, `cast-char-boundedUInt` and
  `cast-int-char` in `support.ss`.

## Strings (v1)

- **SEM-STR-1 (v1).** A `String` is a finite sequence of Unicode scalar values.
  A string literal denotes the sequence Idris stores in the elaborated TT
  constant.
- **SEM-STR-2 (v1).** A string primitive applied to literal arguments means
  what Idris's evaluator computes for it (`src/Core/Primitives.idr`). In
  particular:
  - `prim__strAppend` concatenates;
  - `prim__strCons c s` prepends `c`;
  - `prim__cast_CharString c` is the one-character string;
  - `prim__cast_TString n` is the decimal representation of `n`: an optional
    `-` followed by digits with no leading zeros, as Chez's `number->string`
    produces.

  Compile-time evaluation (`ELIM-G-6`) MUST agree with the evaluator. Tests
  check this with `Refl` proofs.

## Doubles (v2)

`Double` follows IEEE 754 binary64, as the Chez backend computes it
(`docs/research/v2-entry.md` records the probes).

- **SEM-DBL-1 (v2).** A `Double` is an IEEE 754 binary64 value, including
  `-0.0`, the infinities and NaN. A literal denotes the double Idris stores
  in the elaborated TT constant. A match on a `Double` literal is excluded
  (`PROF-PRIM-2`); compare with `prim__eq_Double` instead.
  - Test: `tests/profile/v2/reject/PROF-PRIM-2-double-match.idr`
- **SEM-DBL-2 (v2).** `prim__add_Double`, `sub`, `mul`, `div` and
  `prim__negate_Double` are the IEEE operations, rounded to nearest, ties to
  even. No operation is contracted, reassociated or otherwise relaxed. The
  comparisons `lt`, `lte`, `eq`, `gte`, `gt` are false when an operand is
  NaN, and `0.0` equals `-0.0`; the result is an `Int`, `1` or `0`.
  - Test: `tests/e2e/v2/double-basics`
- **SEM-DBL-3 (v2).** `prim__doubleExp`, `Log`, `Pow`, `Sin`, `Cos`, `Tan`,
  `ASin`, `ACos` and `ATan` return what the platform's C library (`libm`)
  returns: the reference backend calls the same functions (`flexp` and so on
  import them). `prim__doubleSqrt`, `Floor` and `Ceiling` are the exact IEEE
  operations. See `SEM-DEV-2`.
  - Test: `tests/e2e/v2/double-basics`
- **SEM-DBL-4 (v2).** `prim__cast_TDouble n` is the double nearest to `n`,
  ties to even. `prim__cast_DoubleT x` truncates `x` toward zero and then
  wraps it (`wrap_T`); if `x` is NaN or infinite it crashes with "cast of a
  non-finite Double" (Chez raises an exception; `SEM-DEV-1` applies). This
  is `exact-truncate` in `Common.idr`. Casts between `Char` and `Double` are
  excluded (`PROF-PRIM-2`).
  - Test: `tests/e2e/v2/double-basics`, `tests/e2e/v2/double-cast-nan`
- **SEM-DBL-5 (v2).** `prim__cast_DoubleString x` is Chez's `number->string`:
  - the shortest decimal digits that read back as `x`, the closest to `x`
    when there are several, and the larger when two are equally close (the
    free-format algorithm of Burger and Dybvig, where Ryu rounds to even);
  - positional notation exactly when `1e-3 ≤ |x| < 1e10`, with at least one
    digit after the point (`100.0`, `0.001`);
  - otherwise `d[.ddd]e[-]x`, with a point only when there is more than one
    digit (`1e22`, `1.5e-7`);
  - `-0.0`, `+nan.0`, `+inf.0`, `-inf.0`;
  - a subnormal ends with `|p`, where `p` is the number of significant bits
    (`5e-324|1`).

  `prim__cast_StringDouble` is Chez's `string->number`; like every string
  primitive it is evaluated at compile time (`PROF-PRIM-4`).
  - Test: `tests/e2e/v2/double-basics`, `tests/tooling/test_dev.py` (the
    printer's tables), and 176,000 fuzzed values in
    `tests/e2e/v2/double-print-fuzz`

## Integers (v3)

- **SEM-BIG-1 (v3).** An `Integer` exists only at compile time. Its
  primitives (`add` … `xor`, `negate`, comparisons, casts to and from the
  other types, and to and from `String`) are evaluated during
  specialization with Idris's own `Integer` primitives, which are the
  reference's (`SEM-REF-1`), and a function whose result is an `Integer` is
  evaluated where it is called, recursion included, up to a depth of
  10,000. An `Integer` that would exist at runtime is rejected
  (`PROF-TYPE-4`): one computed from a runtime value, or passed where a
  runtime value goes. A cast to a fixed-width type wraps (`SEM-INT-7`).
  This is what lets integer literals of the Prelude's `Num`, which are
  `fromInteger` of an `Integer`, become machine constants.
  - Check: `Simplify` (`SBig` values, `foldBig`)
  - Test: `tests/profile/v3/accept/SEM-BIG-1-static-integers.idr`,
    `tests/profile/v1/reject/PROF-TYPE-4-integer.idr`

## Recursive data (v3)

- **SEM-REC-1 (v3).** A recursive data type (one whose values can contain
  values of the same type, directly or through other types) exists at
  compile time only, as `Integer` does (`SEM-BIG-1`): its values are built
  and taken apart during specialization, and a function over it is
  specialized for each value it receives. A value whose constructor would be
  chosen at runtime is rejected (`PROF-DATA-3`). This is how the Prelude's
  `Nat` (in `Prec`, which `show` takes) and small static lists work before
  there is a heap.
  - Check: `Frontend.Translate.dataInstance` (a recursive occurrence makes
    the type static), `Simplify` (`staticReason`)
  - Test: `tests/profile/v3/accept/SEM-REC-1-static-list.idr`,
    `tests/profile/v3/reject/PROF-DATA-3-runtime-list.idr`

## Laziness (v1)

- **SEM-LAZY-1 (v1).** `Delay e` does not evaluate `e`. `Force` of a delayed
  value evaluates `e` at that point. Whether a second `Force` evaluates `e`
  again is unspecified: `e` is pure, so repeating it can change only running
  time, since a crash or non-termination would already have happened at the
  first `Force`.

## Data

- **SEM-DATA-1 (v0).** A data value is a constructor applied to its field
  values. Pattern matching can observe only the constructor and the runtime
  fields.
  - Values have no identity: no address, no sharing, no pointer equality.
  - Representation is not observable.
- **SEM-DATA-2 (v0).** A branch that Idris's coverage check marks impossible
  (`Impossible` in the case tree) is never taken by a profile program. This
  relies on `PROF-ESC-1`.

## Quantities

- **SEM-Q-1 (v0).** Quantity 0 means absent at runtime (`SEM-EVAL-3`).
- **SEM-Q-2 (v0).** Quantity 1 has no runtime meaning in v0. In particular it
  does not imply that a value is unshared.

## IO (v1)

- **SEM-IO-1 (v1).** An IO action is a function of the world token
  (`PrimIO a = (1 w : %World) -> IORes a`). Running `main` applies it to the
  initial world exactly once. Effects happen in the order of the world
  chain: an effect happens when the primitive that consumes its world is
  evaluated. Idris's quantity checker makes the chain linear, so this order
  is total.
- **SEM-IO-2 (v1).** `putStr s` writes the UTF-8 encoding of `s` to standard
  output. `putChar c` writes the UTF-8 encoding of `c`.
  - This is our module's definition. The stock Prelude's `putChar` calls C
    `putchar` and writes a single byte.
- **SEM-IO-3 (v1).** `getChar` reads the next UTF-8 encoded scalar value from
  standard input.
  - At end of input it returns `'\0'`, as Chez's `blodwen-get-char` does.
  - A malformed byte sequence yields U+FFFD for each maximal invalid
    subsequence.
- **SEM-IO-4 (v1).** Output is written in effect order. All output produced
  before the process ends is written on every exit path: normal return,
  `exit`, and crash. Pending output is written before the program blocks
  reading standard input.
- **SEM-IO-5 (v1).** `exit n` ends the process after writing pending output,
  with status `n mod 256`.
- **SEM-IO-6 (v1).** If standard output or standard input fails (for example
  a closed pipe), the behaviour is unspecified in v1.
  - Check: review (the behaviour is unspecified)

## Programs, crashes and resources

- **SEM-PROG-1 (v0).** Running a `main : Int` program evaluates `main`. If it
  produces `v`, the process writes nothing to stdout or stderr and exits
  with status `v mod 256` (the low 8 bits of `v`).
- **SEM-PROG-2 (v1).** Running a `main : IO ()` program runs `main`
  (`SEM-IO-1`). If it returns, the process writes pending output and exits
  with status 0.
- **SEM-CRASH-1 (v0).** A crash ends the process. It writes a diagnostic to
  stderr, writes nothing to stdout, and exits with status 1. The diagnostic
  text is implementation-defined and SHOULD name the cause, for example
  `division by zero`.
- **SEM-CRASH-2 (v3).** Applying a function to an argument that none of its
  clauses matches crashes (`SEM-CRASH-1`), with a message naming the
  function. This is the reference's "Unhandled input" error; like the other
  crashes, Chez writes it differently (`SEM-DEV-1`).
  - Test: `tests/e2e/v3/missing-case`
- **SEM-RES-1 (v0).** Exhausting the stack ends the process abnormally. The
  exit status and any output are unspecified.
  - Check: review (the behaviour is unspecified)
- **SEM-RES-2 (v0).** A self tail call (`LOW-TAIL-1`) uses constant stack.
  A function whose only recursion is self tail calls runs in stack space
  that does not grow with the number of iterations.

## Deviations from the Chez backend

- **SEM-DEV-1 (v0).** Chez reports a crash differently:
  - `idris_crash` writes to stdout and exits with status 1
    (`blodwen-error-quit`);
  - division by zero raises a Scheme exception.

  This compiler always follows `SEM-CRASH-1`. Differential tests
  (`TEST-DIFF-1`) compare only the exit status and stdout written before the
  crash, never the crash message.
- **SEM-DEV-2 (v2).** LLVM treats the `libm` functions as known functions.
  It may evaluate them at compile time with the compiler's own `libm`, or
  replace a call with an equivalent that is exact (`pow(x, 2.0)` with
  `x * x`). The result then differs from the reference only where `libm`
  itself is not correctly rounded, by at most one unit in the last place.
  `Simplify` folds these functions with the Idris compiler's own `Double`
  operations, which run on the same `libm` as the reference.
  - Check: review (a statement about LLVM and the platform)

## Excluded from v0

- **SEM-EXCL-1.** `negate`, `shl` and `shr` are excluded (`PROF-PRIM-2`):
  - Chez computes `negate` with an unwrapped `-`, so `negate MIN` leaves the
    type's range;
  - Chez shifts accept amounts that are negative or at least the width, which
    LLVM treats as poison.

  A version that admits them MUST first specify them here.
- **SEM-EXCL-2.** `Integer` at runtime is excluded until the memory design
  gives it a representation; at compile time it is `SEM-BIG-1` (v3).
  `Double` is specified by `SEM-DBL-*` from v2; its other primitives (casts
  to and from `Char`, matching on literals) stay excluded.
