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

## Evaluation

- **SEM-EVAL-1 (v0).** Evaluation is strict (call by value).
  - The arguments of a call, the fields of a constructor application, and the
    bound expression of a `let` are evaluated before the call, the
    construction, or the `let` body.
  - Only the selected alternative of a match is evaluated.
- **SEM-EVAL-2 (v0).** The order in which the arguments of one call are
  evaluated is unspecified. In v0 the only observable effect of evaluation is
  a crash (`SEM-CRASH-1`), and every crash has the same exit status, so the
  order changes at most the message text. The implementation evaluates left
  to right.
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

## Programs, crashes and resources

- **SEM-PROG-1 (v0).** Running a program evaluates the root `main : Int`. If
  it produces `v`, the process writes nothing to stdout or stderr and exits
  with status `v mod 256` (the low 8 bits of `v`).
- **SEM-CRASH-1 (v0).** A crash ends the process. It writes a diagnostic to
  stderr, writes nothing to stdout, and exits with status 1. The diagnostic
  text is implementation-defined and SHOULD name the cause, for example
  `division by zero`.
- **SEM-RES-1 (v0).** Exhausting the stack ends the process abnormally. The
  exit status and any output are unspecified.
- **SEM-RES-2 (v0).** A self tail call (`LOW-TAIL-1`) uses constant stack.
  A function whose only recursion is self tail calls runs in stack space
  that does not grow with the number of iterations.

## Deviations from the Chez backend

- **SEM-DEV-1 (v0).** Chez reports a crash differently:
  - `idris_crash` writes to stdout and exits with status 1
    (`blodwen-error-quit`);
  - division by zero raises a Scheme exception.

  This compiler always follows `SEM-CRASH-1`. v0 programs have no output, so
  only the stream and the text differ.

## Excluded from v0

- **SEM-EXCL-1.** `negate`, `shl` and `shr` are excluded (`PROF-PRIM-2`):
  - Chez computes `negate` with an unwrapped `-`, so `negate MIN` leaves the
    type's range;
  - Chez shifts accept amounts that are negative or at least the width, which
    LLVM treats as poison.

  A version that admits them MUST first specify them here.
- **SEM-EXCL-2.** `Double`, `Char`, `Integer`, `String`, and their
  primitives are excluded until a version specifies them here. That includes
  NaN and infinity in casts: Chez's `exact-truncate` fails on them.
