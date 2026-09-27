# 02. The profile: a strict subset of Idris 2

**Contract document.** Changes need the user's approval
([00-index](00-index.md#change-process)).

The profile is the part of Idris 2 this compiler accepts. It selects
constructs and adds nothing. This document defines profiles **v0** and
**v1** normatively. Later versions are sketched at the end and become
normative only when adopted.

A rule marked `(vN)` applies from version N on. A rule marked `(vN only)`
applies to version N and is replaced by the rule it names in later versions.

## General rules

- **PROF-GEN-1 (v0).** Every program in the profile is an ordinary Idris 2
  program. The pinned stock Idris accepts it, and it means what
  [03-semantics](03-semantics.md) says, which agrees with stock Idris.
- **PROF-GEN-2 (v0).** Every rule in this document is enforced by the
  compiler. A violation fails compilation with an `unsupported` error that
  names the rule and points at the Idris source
  ([13-diagnostics](13-diagnostics.md)).
- **PROF-GEN-3 (v0).** Rules are stated at source level but checked on
  checked TT, or, for `PROF-HEAP-*`, on `Core` after the guaranteed
  eliminations. Elaboration inserts implicit arguments, auto-bound names and
  generated definitions that the source does not show. Where the source and
  the checked form disagree, the check on the checked form decides.
- **PROF-GEN-4 (v0).** Each version is a superset of the previous version,
  and adopting a new version changes the meaning of no program already in the
  profile.
- **PROF-GEN-5 (v1).** Source constructs that would need a heap (lambdas,
  partial application, `Lazy`, `IO` actions, string building) are allowed in
  the source. A program is accepted only if every one of them is removed by
  the guaranteed eliminations ([06-elimination](06-elimination.md)), and
  `PROF-HEAP-*` states exactly what may survive. The eliminations are a fixed,
  deterministic list, so acceptance never depends on optimizer heuristics.

Scope of the rules:
- **Reachable** means reachable from the root through any reference in types
  or bodies, at runtime or compile-time positions.
- **Runtime-reachable** means reachable through runtime positions only.

Unless a rule says otherwise, it applies to runtime-reachable definitions.

## Modules and program shape

- **PROF-PROG-1 (v0).** A `main : Int` program is exactly one Idris source
  file, compiled with `--no-prelude`, with no `import` declarations.
  - Check: `Frontend.Main.compileModule`, at the `import`. Idris does not call
    the incremental backend at all for a module that imports a module without
    `mlir` incremental data (any module of the `prelude` package): it prints
    a warning and exits 0 without artifacts. `dev.py compile`
    (`DRV-FLOW-1`) reports that case as this rule.
  - Test: `tests/profile/v0/reject/PROF-PROG-1-import.idr` (through
    `DRV-FLOW-1`)
- **PROF-PROG-2 (v0).** In a `main : Int` program, the module defines
  `main : Int` with no arguments, and `main` is the root. The program is
  compiled with `--inc mlir --check` (`FE-ENTRY-2`).
  - Check: `Frontend.Main.compileModule`, with Idris's entry convention
    from the registry (category 1 of [17-registry](17-registry.md))
  - Test: `tests/profile/v0/reject/PROF-PROG-2-{missing,args}.idr`
- **PROF-PROG-3 (v0).** Definitions that are not reachable are neither
  checked nor compiled. They remain subject to `PROF-PRAG-1`.
- **PROF-PROG-4 (v1).** An IO program has a main module that defines
  `main : IO ()`, and is compiled with `--no-prelude` and `-o`
  (`FE-ENTRY-4`). The root is `main`. Its modules may import only:
  - its other modules (*user modules*), each subject to every rule here;
  - the *trusted modules*: `Builtin` and `PrimIO` from the pinned Idris
    `prelude` package, and from v3 the Prelude's own modules (`Prelude`,
    `Prelude.Basics`, `Prelude.Num` and so on), imported explicitly with
    `import Prelude` (the driver still passes `--no-prelude`). A program's
    IO is the Prelude's (`PROF-IO-4`): this compiler ships no Idris module
    of its own (`PROF-IO-1`).

  Modules of other packages (`base`, `contrib`) are rejected.
  - Check: `Frontend.Main.compileIO`, at the offending `import`; which
    modules are trusted is the library table's (*Trusted*,
    [17-registry](17-registry.md))
  - Test: `tests/profile/v3/reject/PROF-PROG-4-base.idr`,
    `tests/profile/v1/accept/PROF-PROG-4-two-modules/`, `tests/e2e/v3/prelude`

*Note:* conformance fixtures state expected results as Idris proofs, or, for
IO programs, as expected output ([14-testing](14-testing.md)).

## Trusted modules (v1)

- **PROF-LIB-1 (v1).** A reachable definition from a trusted module must be on
  this list. Anything else from a trusted module is rejected with this rule.

  | Module | Admitted definitions |
  | --- | --- |
  | `Builtin` | `Unit`, `MkUnit`, `Pair`, `MkPair`, `fst`, `snd`, `Equal`, `Refl`, `Void`, `id`, `the`, `delay`, `force`; the literal interfaces `FromChar`, `FromString` and, from v2, `FromDouble` (`fromChar`, `fromString`, `fromDouble`, their `Mk` constructors and implementations) and their default hints `defaultChar`, `defaultString`, `defaultDouble`, which elaborate character, string and `Double` literals in polymorphic positions |
  | `PrimIO` | `IORes`, `MkIORes`, `PrimIO`, `IO`, `MkIO`, `prim__io_pure`, `io_pure`, `prim__io_bind`, `io_bind`, `fromPrim`, `toPrim`, `unsafePerformIO`, `unsafeCreateWorld`, `unsafeDestroyWorld` |
  | the Prelude (v3) | every definition, subject where it is reached to every other rule: its lists and `Nat` are compile-time data (`SEM-REC-1`), its `Integer` literals compile-time integers (`SEM-BIG-1`), its `%foreign` primitives other than the IO primitives of `PROF-IO-4` rejected (`PROF-ESC-1`) |
  | `Builtin` (v3) | also every other definition but its escape hatches `believe_me`, `idris_crash` and `assert_linear`: the proof combinators `sym`, `trans`, `replace`, `rewrite__impl`, `DPair` |
  | the base library (v3) | see `PROF-LIB-3` |

  - Check: `Frontend.Profile.checkReachable`, with the library table of
    [17-registry](17-registry.md) (*Trusted*, *Admitted*, and what `PrimIO`
    admits). `Builtin`'s escape hatches are rejected on Idris's flag
    (`PROF-ESC-1`) before admission is asked.
  - Test: `tests/profile/v3/accept/PROF-LIB-1-equality-proofs.idr`
- **PROF-LIB-3 (v3).** The modules of the base library under `Data`,
  `Control`, `Decidable` and `Syntax` are trusted like the Prelude, when the
  program is built with `-p base`: every definition is admitted, subject
  where it is reached to every other rule. `System.*` (the FFI, files,
  processes, clocks) is not trusted.
  - Check: the library table of [17-registry](17-registry.md) (*Trusted*,
    base's areas), which recognizes them by namespace
  - Test: `tests/e2e/v3/vect`, `tests/profile/v3/reject/PROF-PROG-4-base.idr`
- **PROF-LIB-2 (v1).** Pragmas inside trusted modules are allowed. Their
  effects are not: the compiler ignores `%default` and other elaboration
  flags, and from v3 takes `%inline` as a hint to unfold (`ELIM-G-19`). It
  honours `%foreign` and `%extern` only for the IO primitives the registry
  lists (`PROF-IO-4`): a `%foreign` definition by the spec it declares for
  backends (`C:idris2_putStr`), whose Idris name and type are validated
  (`HOOK-SHAPE-1`), and an `%extern` one by its name
  ([17-registry](17-registry.md)).

## IO (v1)

- **PROF-IO-1.** *Withdrawn after v3:* this compiler's own IO module,
  `IdrisMLIR.IO` (the package `idris-mlir-io`), is removed: programs use
  Idris's own libraries ([the plan](../plan.md), decision 1), and its
  programs moved to the Prelude's IO (`PROF-IO-4`). A program that still
  imports it no longer compiles, a deliberate exception to `PROF-GEN-4`.
  Its `exit` and its UTF-8 `getChar` have no counterpart in the trusted
  modules (`SEM-IO-5`, `SEM-IO-3`).
- **PROF-IO-2.** *Withdrawn after v3:* the module's four `%foreign`
  primitives went with it (`PROF-IO-1`). The IO primitives the compiler
  maps to `idr.io` ops are the Prelude's (`PROF-IO-4`).
- **PROF-IO-4 (v3).** A program's IO is the Prelude's. Its primitives in
  `Prelude.IO` map to `idr.io` ops ([08](08-idr-dialect.md)):
  `prim__putStr` and `prim__putChar` are `idr.io.put_str` and
  `idr.io.put_char`, and `prim__getChar` is `idr.io.get_byte`. So the
  Prelude's `putStr`, `putStrLn`, `putChar`, `print`, `printLn` and
  `getChar` work through its `HasIO IO`, and `do` through its `Monad IO`.
  Their meaning is `SEM-IO-2` and `SEM-IO-7`. The stock Chez backend runs
  the same program, so every IO fixture is also a differential test
  (`TEST-DIFF-1`); `SEM-IO-2` says where the two backends' output agrees.
  The Prelude's other `%foreign` primitives (`getLine`, files, time) stay
  rejected (`PROF-ESC-1`).
  - Check: the registry's `IOCall` entries of category 1
    ([17-registry](17-registry.md)), handled by
    `Frontend.Translate.application` and `Frontend.Profile.checkReachable`
  - Test: `tests/e2e/v3/prelude-io`,
    `tests/profile/v1/accept/PROF-LIB-2-io-library.idr`
- **PROF-IO-3 (v1).** User modules do not use `unsafePerformIO`,
  `unsafeCreateWorld`, `unsafeDestroyWorld` or `%MkWorld`. These are reachable
  only through the root term `unsafePerformIO main` that Idris builds for `-o`.
  So effects happen only in the single world chain that starts at `main`
  (`SEM-IO-1`).
  - Check: `Frontend.Profile.checkReachable`, on the three definitions the
    registry forbids under this rule (category 2 of
    [17-registry](17-registry.md))
  - Test: `tests/profile/v1/reject/PROF-IO-3-unsafe-perform.idr`. The other
    names cannot be written in a user module: `unsafeCreateWorld` and
    `unsafeDestroyWorld` are private to `PrimIO`, and `%MkWorld` is a pragma
    token (`PROF-PRAG-1`).

## Runtime types

- **PROF-TYPE-1 (v0).** The runtime types of v0 are:
  - `Int`, `Int8`, `Int16`, `Int32`, `Int64`;
  - `Bits8`, `Bits16`, `Bits32`, `Bits64`;
  - profile data types (`PROF-DATA-*`).
- **PROF-TYPE-2 (v0 only; replaced by PROF-TYPE-4).** The type of every
  runtime position MUST normalize, by Idris's own normalizer in its context,
  to a closed runtime type. This excludes at runtime:
  - `Integer`, `Double`, `Char`, `String`, `%World`;
  - `Type`;
  - function types;
  - `Lazy` and `Inf`;
  - types with free variables;
  - types that depend on runtime values.
  - Test: superseded in v1 (`PROF-TYPE-4`)
- **PROF-TYPE-3 (v0).** Compile-time positions (quantity 0) may have any type
  that stock Idris accepts, subject to `PROF-ESC-1`.
  - Test: `tests/profile/v0/accept/PROF-TYPE-3-erased-witness.idr`
- **PROF-TYPE-4 (v1).** After monomorphisation, the type of every runtime
  position normalizes to a closed type built from:
  - the v0 integer types, `Char`, `String` and `%World`;
  - `Double`, from v2;
  - profile data types, instantiated;
  - function types and `Lazy`, which must then be eliminated
    (`PROF-HEAP-1`, `PROF-HEAP-2`).

  Still excluded at runtime:
  - `Integer`, which from v3 exists at compile time only (`SEM-BIG-1`), and
    `Double` before v2;
  - `Type`;
  - `Inf` (codata) before v3, which from v3 is a suspension like `Lazy`
    (`SEM-REC-2`);
  - types that depend on runtime values.
  - Check: `Frontend.Translate.coreType`, on each instance (monomorphisation
    happens during translation, `CORE-PASS-1`)
  - Test: `tests/profile/v1/reject/PROF-TYPE-4-{integer,dependent}.idr`

## Data types

- **PROF-DATA-1 (v0 only; replaced by PROF-DATA-5).** A data type used at
  runtime is declared in the program's module, and its type constructor has
  type `Type`: no parameters and no indices. Records are data types.
  - Test: superseded in v1
- **PROF-DATA-2 (v0).** Every constructor field in a runtime position has a
  runtime type of the current version. Quantity-0 fields may have any type.
  - Test: `tests/profile/v0/reject/PROF-DATA-2-type-field.idr`,
    `tests/profile/v0/accept/PROF-DATA-2-erased-field.idr`
- **PROF-DATA-3 (v0).** Runtime data types are not recursive. In the graph
  with an edge T → U whenever a constructor of T has a runtime field of type
  U, after instantiation, no cycle is reachable from a runtime data type.
  Quantity-0 fields add no edges. From v3 a recursive data type is a
  compile-time type (`SEM-REC-1`), and this rule rejects a value of one
  that a recursion on a runtime value builds, so that no finite choice of
  known shapes stands for it. A choice among values of known shapes is not
  rejected (`ELIM-G-20`).
  - Check: `Frontend.Translate.dataInstance`, `Simplify`; dialect verifier
    `IDR-DATA-4`
  - Test: `tests/profile/v3/reject/PROF-DATA-3-runtime-list.idr`
- **PROF-DATA-4 (v0).** Data types with zero constructors are allowed. Their
  values cannot exist at runtime.
  - Test: `tests/profile/v0/accept/PROF-DATA-4-void.idr`
- **PROF-DATA-5 (v1).** A runtime data type is declared in a user module or
  admitted by `PROF-LIB-1`. It may have parameters (instantiated by
  monomorphisation, `ELIM-MONO-*`). Before v3 it had no indices; from v3 an
  inductive family is admitted, and its indices are compile-time
  information (`SEM-IDX-1`).
  - Test: `tests/profile/v1/accept/PROF-DATA-5-pair-maybe.idr`,
    `tests/profile/v3/accept/SEM-IDX-1-indexed-tags.idr`

## Functions

- **PROF-FN-1 (v0).** Every runtime-reachable definition is one of:
  - a function defined by pattern matching in a user module (including the
    auxiliary definitions Idris generates for `case`, `with` and `where`);
  - a data constructor of a profile data type;
  - a primitive allowed by `PROF-PRIM-*`;
  - a definition admitted by `PROF-LIB-1`.
  - Check: `Frontend.Translate.application`
  - Test: review. A pragma-free user module reaches no other kind of
    definition: `%extern` and `%foreign` are pragmas (`PROF-PRAG-1`) and
    holes are escape hatches (`PROF-ESC-1`), both reported first.
- **PROF-FN-2 (v0 only; replaced by PROF-FN-7).** Every function's type is a
  telescope ending in a runtime type, with as many binders as its case tree
  has arguments.
  - Test: superseded in v1
- **PROF-FN-3 (v0 only; replaced by PROF-FN-7).** No partial application.
  - Test: superseded in v1
- **PROF-FN-4 (v0 only; replaced by PROF-FN-7).** No lambda in a runtime
  position.
  - Test: superseded in v1
- **PROF-FN-5 (v0).** Before v3, every runtime-reachable function's own
  patterns cover every case: Idris's coverage check reports no missing
  cases. From v3 a function with missing cases is allowed, and a missing
  case crashes (`SEM-CRASH-2`); the Prelude's `div` and `mod` are written
  that way. Idris treats `prim__div_T` and `prim__mod_T` as partial, so a
  function that divides must be declared `partial` (or the module sets
  `%default partial`); dividing by zero is a defined crash (`SEM-INT-4`).
  Termination is not required.
  - Check: `Frontend.Translate.translateInstance`
  - Test: `tests/e2e/v3/missing-case`,
    `tests/profile/v0/accept/PROF-FN-5-{nonterminating,division}.idr`
- **PROF-FN-6 (v0).** Recursion, including mutual recursion, is allowed.
  - Test: `tests/profile/v0/accept/PROF-FN-6-{fib,mutual,tail-loop}.idr`
- **PROF-FN-7 (v1).** Higher-order functions, lambdas, partial application,
  functions returning functions, and polymorphic functions are allowed,
  subject to `PROF-HEAP-*` and `PROF-POLY-1`.
  - Test: `tests/profile/v1/accept/PROF-FN-7-{compose,twice,map-pair,state}.idr`
- **PROF-IFACE-1 (v2).** User-defined interfaces are allowed: superclasses,
  default methods, named implementations, constrained implementations, and
  methods with type variables of their own (higher-kinded interfaces such
  as a user `Monad`). `do` works over any user monad whose `>>=` and `>>`
  are in scope. Every implementation is resolved at compile time
  (`FE-TR-6`); one chosen by a runtime value is rejected (`PROF-HEAP-1`).
  - Test: `tests/e2e/v2/interface-*`
- **PROF-POLY-1 (v1).** Polymorphic recursion is rejected (`ELIM-MONO-3`).
  It is detected when an instance being translated requests an instance of
  the same definition whose static arguments embed its own and are larger
  (from v3; before, any larger instance counted, which also caught a method
  that calls the same method of another implementation, as `compare` on
  the Prelude's `Prec` calls `compare` on `Nat`).
  - Test: `tests/profile/v1/reject/PROF-POLY-1-nested.idr`

## Terms

- **PROF-TERM-1 (v0).** In runtime positions, these forms may appear:
  - local variables;
  - calls and constructor applications;
  - literals of runtime types;
  - allowed primitives;
  - `let` bindings;
  - pattern matching as compiled by Idris into case trees.

  From v1 also: lambdas, `Delay` and `Force` (of `Inf` too from v3), and
  `%MkWorld`.
- **PROF-TERM-2 (v0).** In every version, these forms are forbidden in runtime
  positions:
  - `Type`;
  - metavariables and holes.

  In v0 only, `Delay`, `Force`, `%World` and IO are also forbidden.
  An `Unmatched` case-tree leaf is not forbidden: the definition is covering
  (`PROF-FN-5`), so no input reaches it (`FE-TR-4`).
  - Check: `Frontend.Translate`
  - Test: review. Holes are reported by `PROF-ESC-1`, and `Type` in a
    runtime position by `PROF-TYPE-4`, before this check can see them.

## Primitives

`T` ranges over the integer types
{`Int`, `Int8`, `Int16`, `Int32`, `Int64`, `Bits8`, `Bits16`, `Bits32`, `Bits64`}.

- **PROF-PRIM-1 (v0).** The integer primitives are allowed:
  - `prim__add_T`, `prim__sub_T`, `prim__mul_T`;
  - `prim__div_T`, `prim__mod_T`;
  - `prim__and_T`, `prim__or_T`, `prim__xor_T`;
  - `prim__lt_T`, `prim__lte_T`, `prim__eq_T`, `prim__gte_T`, `prim__gt_T`;
  - `prim__cast_ST` for distinct `S` and `T`.

  Their meaning is `SEM-INT-*`.
  - Test: `tests/e2e/sem.py` (`TEST-SEM-1`)
- **PROF-PRIM-2 (v0).** In every version, these primitives are rejected:
  - `prim__negate_T`, `prim__shl_T`, `prim__shr_T` (`SEM-EXCL-1`);
  - everything on `Integer` before v3; from v3, `Integer` primitives are
    evaluated at compile time (`SEM-BIG-1`), and an `Integer` at runtime is
    a `PROF-TYPE-4` error;
  - casts between `Char` and `Double`, and a match on a `Double` literal
    (`SEM-EXCL-2`);
  - `prim__believe_me` and `prim__crash`, which `PROF-ESC-1` reports first.

  In v0 only, primitives on `Char` and `String` are also rejected, and in v0
  and v1 everything on `Double`.
  - Test: `tests/profile/v0/reject/PROF-PRIM-2-{negate,shl}.idr`,
    `tests/profile/v2/reject/PROF-PRIM-2-double-*.idr`
- **PROF-PRIM-3 (v1).** The `Char` primitives are allowed:
  - `prim__lt_Char`, `prim__lte_Char`, `prim__eq_Char`, `prim__gte_Char`,
    `prim__gt_Char`;
  - `prim__cast_CharT` and `prim__cast_TChar`.

  Their meaning is `SEM-CHAR-*`.
  - Test: `tests/e2e/v1/chars`
- **PROF-PRIM-5 (v2).** The `Double` primitives are allowed:
  - `prim__add_Double`, `sub`, `mul`, `div`, `prim__negate_Double`;
  - `prim__lt_Double`, `lte`, `eq`, `gte`, `gt`;
  - `prim__doubleExp`, `Log`, `Pow`, `Sin`, `Cos`, `Tan`, `ASin`, `ACos`,
    `ATan`, `Sqrt`, `Floor`, `Ceiling`;
  - `prim__cast_TDouble` and `prim__cast_DoubleT` for the integer types `T`;
  - `prim__cast_DoubleString` and `prim__cast_StringDouble`, as string
    primitives (`PROF-PRIM-4`).

  Their meaning is `SEM-DBL-*`.
  - Test: `tests/e2e/v2/double-basics`
- **PROF-PRIM-4 (v1).** Every `String` primitive may appear in the source.
  Each occurrence must be removed by compile-time evaluation or output fusion
  (`ELIM-G-6`, `ELIM-G-7`). A surviving string-building primitive is a
  `PROF-HEAP-3` error. Any other surviving string primitive (`strLength`,
  `strIndex`, string comparison, and so on) is rejected with this rule, and
  from v3 so is a match on a string that is not known at compile time; a
  match on a known string is decided during specialization, and one on a
  choice among known strings is a match on the choice (`ELIM-G-20`).
  - Test: `tests/profile/v1/reject/PROF-PRIM-4-runtime-match.idr`

## Heap freedom (v1)

These are checked by the guaranteed eliminations
([06-elimination](06-elimination.md)), which produce first-order `Core`: a
value these rules forbid has no representation there, so `Simplify` reports
it where it would have to exist at runtime. Each error points at that source
construct, and says which elimination did not apply and why
(`DIAG-HEAP-1`).

- **PROF-HEAP-1 (v1).** No value of function type remains in a runtime
  position: no lambda, partial application, or function-typed parameter,
  field, `let` or result. A function picked at runtime from a known set is
  a choice (`ELIM-G-20`), used through its tag, and is not in a runtime
  position; one that a recursion on a runtime value builds is.
- **PROF-HEAP-2 (v1).** No `Lazy` value remains in a runtime position, in
  the same sense as `PROF-HEAP-1`.
- **PROF-HEAP-3 (v1).** No string-building primitive remains (`strAppend`,
  `strCons`, `strReverse`, `strSubstr`, casts to `String`). So every runtime
  `String` value comes from a string literal, possibly passed through
  variables, arguments, fields and results, and lives in static data.
- **PROF-HEAP-4 (v1).** A recursive function does not pass itself a
  function-typed argument that grows from the one it received. This is
  Futhark's restriction that "a loop may not produce a function"; without it,
  specialization would not terminate. `Simplify` detects it when the
  driver's whistle blows (`ELIM-G-19`): the new call's configuration embeds
  an ancestor's, and the two have no generalization, because a static part
  differs and no runtime value can stand for it. Nested uses on unrelated
  or smaller arguments, such as the `>>` of a `do` block, are not growth.
- **PROF-HEAP-5 (v1).** Arity raising (`ELIM-G-5`) moves code only if that
  code cannot crash and cannot fail to terminate, or if no effect happens
  between building the action and running it. A function that returns an
  action or function after such code, and whose action is run after an
  effect, cannot be raised, and its result survives as a function value;
  the error names the blocking operation.
  - Test: `tests/profile/v1/accept/PROF-HEAP-5-division-run-at-once.idr`
  It is decided once specialization is finished, so any other user error
  found while specializing is reported instead (`DIAG-ONE-1`).
  - Check: `Simplify`; `PROF-HEAP-5` on the finished program
    (`Simplify.Safety`)
  - Test: `tests/profile/v1/reject/PROF-HEAP-{1..5}-*.idr`, and every v1
    accept fixture (the check passes). A function value survives only when
    a recursion on a runtime value builds it; one picked by a match is a
    choice (`tests/e2e/v3/choice`).

## Escape hatches

- **PROF-ESC-1 (v0).** No reachable definition, at runtime or compile-time
  positions, may be or refer to any of:
  - `prim__believe_me` or `prim__crash`;
  - a definition marked as an escape hatch (`isEscapeHatch`);
  - a hole;
  - an `%extern` or `%foreign` definition other than the Prelude's IO
    primitives of `PROF-IO-4`.

  From v3, `assert_total` reached from a library module's own definitions is
  trusted: the library's author asserted it, and it changes no value. It
  stays rejected in user modules.
  - Check: `Frontend.Profile.checkReachable` on TT, and the source scan of
    `PROF-PRAG-1`, which also rejects hole identifiers and the spellings
    `prim__believe_me`, `prim__crash`, `believe_me` and `idris_crash` in user
    modules. The scan is needed because Idris evaluates `prim__believe_me`
    applied to a constructor during elaboration, so it can vanish from TT.
    The spellings, the IO primitives that may be reached, and the trusted
    totality assertion are the registry's entries and policy
    ([17-registry](17-registry.md)); escape hatches are read from Idris's
    flag.
  - Test: `tests/profile/v0/reject/PROF-ESC-1-{believe-me,crash,believe-me-in-proof,hole-in-proof}.idr`

  *Rationale:* the compiler trusts Idris's type checker for data layout and
  for impossible branches. An escape hatch in a proof can equate two
  different runtime types, and `replace` then reinterprets a value's
  layout. So the rule covers compile-time positions too.

## Pragmas

- **PROF-PRAG-1 (v0).** User modules contain no pragma. Every `%`-directive is
  forbidden, except `%default` from v2. Fixity declarations (`infixl` and so
  on) are declarations, not pragmas, and are allowed.
  - Check: `Frontend.Profile.checkPragmas`. It lexes each user module's
    source with Idris's own lexer (`Parser.Lexer.Source`) and rejects every
    other `Pragma` token at its position, including in unreachable code.
  - Test: `tests/profile/v0/reject/PROF-PRAG-1-{inline,transform,unreachable}.idr`,
    `tests/profile/v2/{accept/PROF-PRAG-1-default,reject/PROF-PRAG-1-default-with-inline}.idr`

  *Rationale:* pragmas change elaboration or code generation in ways the
  profile does not specify. Some leave traces in TT (`%inline`, `%transform`,
  `%spec`, `%foreign`); others leave none (`%logging`). Lexing catches them
  all. `%default` changes only the totality Idris demands of a definition,
  not the totality it finds, which is all the compiler reads
  (`PROF-HEAP-5`); without it, every numeric program would mark each
  function that divides `partial`, because the division primitives are
  partial in `Builtin`.

## Later versions (informative until adopted)

| Version | Adds |
| --- | --- |
| v2 | User-defined interfaces, whose dictionaries are eliminated by specialization; `do` over any user monad through a `Monad` interface; `Double` (with semantics added to 03 first) |
| v3 onward | The Prelude's dependency modules, one layer at a time and each fully tested: first the non-recursive parts of `Prelude.Basics`, `Prelude.Types`, `Prelude.Interfaces` and `Prelude.Ops` (`Bool`, `Maybe`, `Either`, `Num`/`Eq`/`Ord` at machine types) |
| after the memory design | recursive data, `Integer`, `Nat` at runtime, strings built at runtime, the stock Prelude imported implicitly |
