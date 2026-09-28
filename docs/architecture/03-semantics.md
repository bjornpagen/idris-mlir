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
    type (`Refl` proofs) MUST equal the compiled program's value. The
    `Refl` oracles check it per fixture (`TEST-ORACLE-1`), and the
    two-level test on closed terms (`TEST-LEVELS-1`). The exceptions are
    the primitives whose value depends on the host (`SEM-HOST-1`).
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
  - The implementation evaluates left to right, the arguments of a curried
    application included: `Emit` writes them in that order (from v3;
    before, they went right to left, which cost `fib` 14% because LLVM's
    tail recursion elimination then looped on the other call).
  - Test: `bench/` (`fib`); `tests/e2e/v3/compile-time-evaluation`
- **SEM-EVAL-3 (v0).** Quantity-0 arguments, fields and `let` bindings are
  never evaluated at runtime.
- **SEM-EVAL-4 (v0).** An evaluation that would crash MUST crash, even if its
  result is unused. No optimization may remove, reorder past an observable
  effect, or speculate an operation that may crash, unless it proves that the
  operation cannot crash (`OPT-SAFE-1`). So a call that may crash is never
  removed (`OPT-CALL-1`), and a compile-time evaluation that crashes leaves
  its call to crash at runtime (`SEM-EVAL-6`).
- **SEM-EVAL-5 (v0).** Non-termination is observable. No optimization may
  remove a computation that may not terminate, or assume that it terminates.
  In particular, the compiler MUST NOT emit LLVM attributes or metadata that
  assert termination or forward progress (`mustprogress`, `willreturn`)
  unless a later version of this document allows it. A loop in a function
  that is not total carries `idr.may_loop` (`LOW-TAIL-4`), so that no pass
  deletes it.

*Note:* the Chez backend's own optimizations may drop unused `let` bindings.
Conformance tests therefore never rely on a crash in dead code; the rules
above bind this compiler regardless.

## Compile-time evaluation

*New at the cutover.* These rules replace the evaluator that `Simplify`
was (`ELIM-G-19`, `SEM-BIG-1`).

- **SEM-EVAL-6 (v3).** Compile-time evaluation is runtime evaluation, run
  early. The compiler evaluates a call at compile time exactly when:
  - it is closed: every argument is a constant (`IDR-CONST-1`), including
    the captures and fields inside it;
  - its callee is total and pure, and so is every function named by a
    closure in its arguments, recursively through captures and fields.

  Such a call is always evaluated, and no other call ever is. Evaluating
  runs the program's own code, lowered as the executable's is, with the
  runtime the executable links (`ELIM-EVAL-1`, `LOW-JIT-1`); so a value
  computed at compile time is the value the executable would compute. A
  call whose evaluation crashes is left in place, and crashes at runtime
  (`SEM-EVAL-4`).
  - **Total** means that Idris's totality checker reports the function
    terminating: `Core.Termination.checkTotal` returns `IsTerminating`.
    That includes the library's own `assert_total` (`PROF-ESC-1`), and
    excludes every function that calls one Idris does not report
    terminating, since the checker's result is transitive. Coverage is not
    part of it: a function with missing cases, or one that divides, is
    total when it terminates, and a missing case is a crash.
  - **Pure** means that the function reaches no IO primitive
    (`IDR-FACT-1`), `unsafePerformIO` in library code included.
  - **Partial code is never evaluated.** A closed call to a partial
    function runs at runtime. If its result has no runtime representation
    in the heap-free profile, the program is rejected with the rule of that
    value (`PROF-TYPE-4`, `PROF-DATA-3`), even if the call would finish.
  - *Rationale:* Idris's typechecker decides differently which terms it
    reduces. It unfolds any definition visible from where it evaluates
    (`reducibleInAny` in `evalRef`, `Core/Normalise/Eval.idr:302`), whether
    or not it is total, and bounds the work by a timer (`checkTimer`,
    `:308`) and optional fuel (`evalDef`, `:531`). A timer cannot decide
    what a compiled program means, and a partial function may not return,
    so this compiler asks for termination instead: every evaluation it
    starts finishes, except when the machine runs out (`EVAL-1`). The rule
    is stricter than the typechecker's, and never more permissive.
  - Check: `idr-eval` (`ELIM-EVAL-1`), with `idr.total` from `Emit`
    (`IDR-FACT-1`)
  - Test: `tests/e2e/v3/compile-time-evaluation`,
    `tests/e2e/v3/static-evaluation`; `TEST-EQUIV-1`
- **SEM-EVAL-7 (v3).** Memory management is not observable. Where a value
  lives (a register, static data, a heap cell, or the arena that the JIT
  allocates from) changes no result (`SEM-DATA-1`). So evaluating at
  compile time, in the JIT's arena, computes what the executable computes.
  - Check: review (a property of the representations, `LOW-JIT-1`)
- **EVAL-1 (v3).** A compile-time evaluation that the machine cannot
  finish is a compile error that names the call. By `SEM-EVAL-6` it would
  finish on a large enough machine; the compiler's own stack (reserved as
  large as the address space allows) or memory ran out first. It is not a
  profile rejection, since the program is in the profile.
  - The error names the call and its location, and says which resource ran
    out. `idris-mlir-cc` exits with status 4 (`DRV-CC-2`), and the frontend
    reports it as an Idris error at the call.
  - `--no-eval` compiles the program without evaluating (`DRV-CC-1`); a
    program so compiled means the same.
  - Check: `idr-eval`: a fault on the evaluation stack's guard, a failed
    arena mapping, or the child killed by the kernel for memory
    (`ELIM-EVAL-1`)
- **SEM-HOST-1 (v3).** Two kinds of primitive give their value from the
  host that evaluates them:
  - `cast` from `String` to `Double` and to the integer types: Idris's
    typechecker reduces it through its own host (`castDouble` and friends
    in `src/Core/Primitives.idr`, on Chez), while compiled code reads the
    grammar of `SEM-DBL-5`;
  - the `libm` functions of `SEM-DBL-3`: the typechecker runs the host's
    `libm`, and compiled code, at compile time and at runtime, musl's.

  Where such a primitive is reachable from a compile-time position
  (`FE-REACH-1`), so that a type could depend on its value, the program is
  rejected with this rule: the two levels could disagree (`SEM-REF-1`).
  - *planned* (v3; [the plan](../plan.md), section 1): the check in
    `Frontend.Profile.checkReachable`, and the reject fixtures
    `tests/profile/v3/reject/SEM-HOST-1-*`

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
- **SEM-STR-2 (v1).** A string primitive means what Idris's evaluator
  computes for it (`src/Core/Primitives.idr`). In particular:
  - `prim__strAppend` concatenates;
  - `prim__strCons c s` prepends `c`;
  - `prim__cast_CharString c` is the one-character string;
  - `prim__cast_TString n` is the decimal representation of `n`: an optional
    `-` followed by digits with no leading zeros, as Chez's `number->string`
    produces;
  - `strLength` counts scalar values, and `strIndex` indexes by them.

  *Revised at the cutover:* the compiler has one implementation of each
  string primitive, the runtime's (`LOW-STR-2`). Folders and compile-time
  evaluation call the same functions (`SEM-EVAL-6`, `LOW-RT-1`), so no
  primitive has a second meaning inside the compiler. The `Refl` oracles
  and the two-level test hold the runtime to Idris's evaluator
  (`TEST-LEVELS-1`).

## Doubles (v2)

`Double` follows IEEE 754 binary64, as the Chez backend computes it.

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
  operations. See `SEM-DEV-2`. *Revised at the cutover:* this compiler runs
  one `libm`, musl's, at compile time (inside `idris-mlir-cc`) and at
  runtime; Idris's typechecker runs the host's, which is why such a value
  may not reach a type (`SEM-HOST-1`).
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

  *Revised at the cutover:* the digits come from Ryu (Adams, PLDI 2018),
  vendored, with a wrapper that detects an exact tie and takes the larger
  candidate (`LOW-DBL-2`).

  `prim__cast_StringDouble s` reads the whole of `s`; a string that is not
  a number is `0.0`, as Idris's frame (`cast-num` in `support.ss`) says.
  Which strings are numbers Idris leaves to the host, so this compiler
  defines it, at compile time and at runtime alike (*revised at the
  cutover*; before, it was Chez's `string->number`, evaluated at compile
  time only):
  - the whole string is fast_float's `general` format: an optional sign
    (`+` allowed), digits with an optional point and an optional exponent
    (`.5` and `5.` included), or `inf`, `infinity` or `nan` in any case;
  - the value is correctly rounded to nearest, ties to even; an exponent
    out of range gives ±infinity or ±0;
  - anything else is `0.0`, surrounding spaces, `1d3`, `1/2`, `0x10` and
    `1_000` included.

  Idris's typechecker may read such a string differently, so the cast may
  not reach a type (`SEM-HOST-1`).
  - Test: `tests/e2e/v2/double-basics`, and 176,000 fuzzed values in
    `tests/e2e/v2/double-print-fuzz`

## Integers (v3)

- **SEM-BIG-1.** *Withdrawn at the cutover:* an `Integer` existed at
  compile time only, and `Simplify` evaluated `Integer` code whatever its
  totality. An `Integer` is now a runtime value (`!idr.big`, `IDR-TY-8`),
  with the meaning of Idris's evaluator. Compile-time evaluation runs the
  program's own code on total calls only (`SEM-EVAL-6`); a big that
  remains at runtime is rejected by the heap-free profile (`PROF-TYPE-4`),
  because it may allocate.

## Recursive data (v3)

- **SEM-REC-1 (v3).** A recursive data type (one whose values can contain
  values of the same type, directly or through other types) is boxed: its
  values are cells, and a field of one refers to another (`IDR-TY-6`,
  `IDR-DATA-4`). *Revised at the cutover:* before, it existed at compile
  time only, its values built during specialization, and a value picked
  at runtime among known shapes was a choice (`ELIM-G-20`).
  - A constant of recursive data (a list written in the program, or one a
    compile-time evaluation returns) is static data (`LOW-CONST-1`), and
    allocates nothing at runtime.
  - A cell built at runtime from values that are not all constants is a
    heap allocation, which the heap-free profile rejects where it survives
    the optimizations (`PROF-DATA-3`).
  - `Nat`-like types are not boxed: they are bigs (`IDR-IN-3`).
  - Check: `Frontend.Translate.dataInstance` (the representation);
    `idr-check-profile` (`PROF-DATA-3`)
  - Test: `tests/profile/v3/accept/SEM-REC-1-static-list.idr`,
    `tests/profile/v3/reject/PROF-DATA-3-runtime-list.idr`
- **SEM-REC-2 (v3).** A value of recursive data is built where it is
  written, strictly, as Idris builds it (`SEM-EVAL-1`). Its fields may hold
  runtime values (`map (* n) [1 .. 10]` is ten runtime products). `Inf` is
  a suspension like `Lazy`: a closure of no arguments, forced by applying
  it (`IDR-TY-7`), so codata (the Prelude's `Stream`, from which its ranges
  are built) is unfolded only as far as it is forced. *Revised at the
  cutover:* a call that returns recursive data is evaluated at compile
  time when `SEM-EVAL-6` says so, and otherwise builds its cells at
  runtime; the driver's whistle and budget (`ELIM-G-19`) are gone.
  - Check: `Frontend.Translate` (`Inf`); the simplify loop (`OPT-PIPE-5`)
  - Test: `tests/profile/v3/accept/SEM-REC-2-streams.idr`,
    `tests/e2e/v3/prelude-lists`

## Inductive families (v3)

- **SEM-IDX-1 (v3).** An index of an inductive family (the length of a
  `Vect`, the bound of a `Fin`, the sides of `Equal`) is compile-time
  information: no value stores it, and two instances of a family that
  differ only in their indices, or in value parameters, are one data type
  (`Vect 3 Double` and `Vect n Double`). A value of a non-recursive family
  is its constructor's tag and fields; a value of a recursive one is a
  box (`SEM-REC-1`). This is Brady, McBride and McKinna,
  "Inductive families need not store their indices" (TYPES 2003), applied to
  every family. Idris does not put a constructor's parameters first
  (`(::) : {0 len} -> {0 elem} -> ...`); which arguments are parameters is
  read from the constructor's return type.
  - Check: `Frontend.Translate.dataInstance` (`typeParams`,
    `eraseIndices`, `paramLayout`)
  - Test: `tests/profile/v3/accept/SEM-IDX-1-indexed-tags.idr`,
    `tests/e2e/v3/vect`

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
  - These are the Prelude's (`PROF-IO-4`). The reference writes `putStr`'s
    string as UTF-8 too, but implements `putChar` with C `putchar`, which
    writes one byte: the two agree on ASCII characters only. Differential
    tests (`TEST-DIFF-1`) put no other character with `putChar`.
- **SEM-IO-3 (v1).** `idr.io.get_char` reads the next UTF-8 encoded scalar
  value from standard input.
  - At end of input it returns `'\0'`, as Chez's `blodwen-get-char` does.
  - A malformed byte sequence yields U+FFFD for each maximal invalid
    subsequence.

  It was the `getChar` of the module `PROF-IO-1` withdrew, and no profile
  program reaches it since: the Prelude's `getChar` reads bytes
  (`SEM-IO-7`). It lost its end-to-end tests: `tests/idr/e2e/hello.mlir`
  runs it on valid input, and nothing tests malformed input.
- **SEM-IO-4 (v1).** Output is written in effect order. All output produced
  before the process ends is written on every exit path: normal return,
  `exit`, and crash. Pending output is written before the program blocks
  reading standard input.
- **SEM-IO-5 (v1).** `idr.io.exit n` ends the process after writing pending
  output, with status `n mod 256`.
  - It was the `exit` of the module `PROF-IO-1` withdrew, and no profile
    program reaches it since: no trusted module exits. Base's
    `System.exitWith` is outside the profile (`PROF-LIB-3`) and goes
    through `believe_me` and a `%foreign` it rejects (`PROF-ESC-1`).
  - Test: it lost its end-to-end test; `tests/idr/lower/io.mlir` checks its
    lowering, not the exit status. *planned*: an end-to-end test once
    base's `exitWith` enters the profile.
- **SEM-IO-6 (v1).** If standard output or standard input fails (for example
  a closed pipe), the behaviour is unspecified in v1.
  - Check: review (the behaviour is unspecified)

## Programs, crashes and resources

- **SEM-IO-7 (v3).** The Prelude's `getChar` reads one byte of standard
  input and returns it as a character (`0` to `255`), and at the end of
  input returns character `255`: the reference backend implements it with
  C `getchar`. It does not decode UTF-8, as `idr.io.get_char` does
  (`SEM-IO-3`); the two read the same buffered input (`LOW-IO-4`).
  - Test: `tests/e2e/v3/prelude-input`
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
- **SEM-RES-2 (v0).** A self tail call uses constant stack: `idr-tail-loops`
  makes it a loop (`LOW-TAIL-5`).
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
  *Revised at the cutover:* LLVM folds them inside `idris-mlir-cc`, which
  is linked with musl, the executable's `libm` too; the compiler has no
  folder of its own for them.
  The reference runs the host's `libm`, which need not agree with musl's
  where neither is correctly rounded: a test whose outputs include `libm`
  results names those lines (`libm-lines`), and on them the comparison with
  Chez allows one unit in the last place.
  - Check: review (a statement about LLVM and the platform)
  - Test: `tests/e2e/v2/double-basics` (`libm-lines`)

## Excluded from v0

- **SEM-EXCL-1.** `negate`, `shl` and `shr` are excluded (`PROF-PRIM-2`):
  - Chez computes `negate` with an unwrapped `-`, so `negate MIN` leaves the
    type's range;
  - Chez shifts accept amounts that are negative or at least the width, which
    LLVM treats as poison.

  A version that admits them MUST first specify them here.
- **SEM-EXCL-2.** *Revised at the cutover:* `Integer` has a representation
  (`!idr.big`); at runtime only the heap-free profile excludes it
  (`PROF-TYPE-4`), until the memory design.
  `Double` is specified by `SEM-DBL-*` from v2; its other primitives (casts
  to and from `Char`, matching on literals) stay excluded.
