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
  - Check: `Frontend.Profile.programShape`
  - Test: `tests/profile/v0/reject/PROF-PROG-1-import.idr`
- **PROF-PROG-2 (v0).** In a `main : Int` program, the module defines
  `main : Int` with no arguments, and `main` is the root. The program is
  compiled with `--inc mlir --check` (`FE-ENTRY-2`).
  - Check: `Frontend.Roots.findRoot`
  - Test: `tests/profile/v0/reject/PROF-PROG-2-{missing,args}.idr`
- **PROF-PROG-3 (v0).** Definitions that are not reachable are neither
  checked nor compiled. They remain subject to `PROF-PRAG-1`.
- **PROF-PROG-4 (v1).** An IO program has a main module that defines
  `main : IO ()`, and is compiled with `--no-prelude` and `-o`
  (`FE-ENTRY-4`). The root is `main`. Its modules may import only:
  - its other modules (*user modules*), each subject to every rule here;
  - the *trusted modules*: `Builtin` and `PrimIO` from the pinned Idris
    `prelude` package, and `IdrisMLIR.IO`, which ships with this compiler
    (`PROF-IO-*`).
  - Check: `Frontend.Profile.programShape`
  - Test: `tests/profile/v1/reject/PROF-PROG-4-{prelude,base}.idr`,
    `tests/profile/v1/accept/PROF-PROG-4-two-modules/`

*Note:* conformance fixtures state expected results as Idris proofs, or, for
IO programs, as expected output ([14-testing](14-testing.md)).

## Trusted modules (v1)

- **PROF-LIB-1 (v1).** A reachable definition from a trusted module must be on
  this list. Anything else from a trusted module is rejected with this rule.

  | Module | Admitted definitions |
  | --- | --- |
  | `Builtin` | `Unit`, `MkUnit`, `Pair`, `MkPair`, `fst`, `snd`, `Equal`, `Refl`, `Void`, `id`, `the`, `delay`, `force` |
  | `PrimIO` | `IORes`, `MkIORes`, `PrimIO`, `IO`, `MkIO`, `prim__io_pure`, `io_pure`, `prim__io_bind`, `io_bind`, `fromPrim`, `toPrim`, `unsafePerformIO`, `unsafeCreateWorld`, `unsafeDestroyWorld` |
  | `IdrisMLIR.IO` | every definition (`PROF-IO-1`) |

  - Check: `Frontend.Profile.trusted`
  - Test: `tests/profile/v1/reject/PROF-LIB-1-believe-me.idr`
- **PROF-LIB-2 (v1).** Pragmas inside trusted modules are allowed. Their
  effects are not: the compiler ignores `%inline`, `%default` and other
  elaboration flags. It honours `%foreign` only for the four primitives of
  `IdrisMLIR.IO`, which it recognizes by full name (`PROF-IO-2`); the
  `%foreign` strings themselves are never read.

## The `IdrisMLIR.IO` module (v1)

- **PROF-IO-1 (v1).** `IdrisMLIR.IO` lives in `lib/idris-mlir-io/`. It
  imports `Builtin` and `PrimIO` publicly and exports exactly:

  ```idris
  export infixl 1 >>=, >>
  pure     : a -> IO a
  (>>=)    : IO a -> (a -> IO b) -> IO b
  (>>)     : IO () -> Lazy (IO b) -> IO b
  putStr   : String -> IO ()
  putStrLn : String -> IO ()        -- putStr (s ++ "\n")
  putChar  : Char -> IO ()
  getChar  : IO Char
  exit     : Int -> IO ()
  ```

  `do` notation desugars to `>>=` and `>>` by name, so it works with no
  interface. `>>` takes `Lazy` for the same reason the stock Prelude does:
  without it, a recursive action would be built eagerly and never stop. The
  semantics are `SEM-IO-*`.
- **PROF-IO-2 (v1).** The module's primitives are four `%foreign`
  definitions:
  - `prim__idrPutStr : String -> PrimIO ()`
  - `prim__idrPutChar : Char -> PrimIO ()`
  - `prim__idrGetChar : PrimIO Char`
  - `prim__idrExit : Int -> PrimIO ()`

  The compiler maps them to `idr.io.*` ops ([08](08-idr-dialect.md)). Each
  also carries a `scheme:` implementation with the same semantics, so every
  IO program also runs on the stock Chez backend for differential testing
  (`TEST-DIFF-1`).
- **PROF-IO-3 (v1).** User modules do not use `unsafePerformIO`,
  `unsafeCreateWorld`, `unsafeDestroyWorld` or `%MkWorld`. These are reachable
  only through the root term `unsafePerformIO main` that Idris builds for `-o`.
  So effects happen only in the single world chain that starts at `main`
  (`SEM-IO-1`).
  - Check: `Frontend.Profile.trusted`
  - Test: `tests/profile/v1/reject/PROF-IO-3-{unsafe-perform,mkworld}.idr`

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
  - Check: `Frontend.Profile.runtimeType`
  - Test: `tests/profile/v0/reject/PROF-TYPE-2-{integer,double,char,string,type,function,poly,dependent}.idr`
- **PROF-TYPE-3 (v0).** Compile-time positions (quantity 0) may have any type
  that stock Idris accepts, subject to `PROF-ESC-1`.
  - Test: `tests/profile/v0/accept/PROF-TYPE-3-erased-witness.idr`
- **PROF-TYPE-4 (v1).** After monomorphisation, the type of every runtime
  position normalizes to a closed type built from:
  - the v0 integer types, `Char`, `String` and `%World`;
  - profile data types, instantiated;
  - function types and `Lazy`, which must then be eliminated
    (`PROF-HEAP-1`, `PROF-HEAP-2`).

  Still excluded at runtime:
  - `Integer`, `Double`;
  - `Type`;
  - `Inf` (codata);
  - types that depend on runtime values.
  - Check: `Frontend.Profile.runtimeType` (after `Mono`)
  - Test: `tests/profile/v1/reject/PROF-TYPE-4-{integer,double,inf,dependent}.idr`

## Data types

- **PROF-DATA-1 (v0 only; replaced by PROF-DATA-5).** A data type used at
  runtime is declared in the program's module, and its type constructor has
  type `Type`: no parameters and no indices. Records are data types.
  - Check: `Frontend.Profile.dataDecl`
  - Test: `tests/profile/v0/reject/PROF-DATA-1-{param,index}.idr`
- **PROF-DATA-2 (v0).** Every constructor field in a runtime position has a
  runtime type of the current version. Quantity-0 fields may have any type.
  - Test: `tests/profile/v0/reject/PROF-DATA-2-integer-field.idr`,
    `tests/profile/v0/accept/PROF-DATA-2-erased-field.idr`
- **PROF-DATA-3 (v0).** Runtime data types are not recursive. In the graph
  with an edge T → U whenever a constructor of T has a runtime field of type
  U, after instantiation, no cycle is reachable from a runtime data type.
  Quantity-0 fields add no edges.
  - Check: `Frontend.Profile.dataDecl`; dialect verifier `IDR-DATA-4`
  - Test: `tests/profile/v0/reject/PROF-DATA-3-{list,mutual}.idr`
- **PROF-DATA-4 (v0).** Data types with zero constructors are allowed. Their
  values cannot exist at runtime.
  - Test: `tests/profile/v0/accept/PROF-DATA-4-void.idr`
- **PROF-DATA-5 (v1).** A runtime data type is declared in a user module or
  admitted by `PROF-LIB-1`. It may have parameters (instantiated by
  monomorphisation, `ELIM-MONO-*`) but no indices: every constructor returns
  the type constructor applied to its parameters unchanged.
  - Test: `tests/profile/v1/accept/PROF-DATA-5-pair-maybe.idr`,
    `tests/profile/v1/reject/PROF-DATA-5-index.idr`

## Functions

- **PROF-FN-1 (v0).** Every runtime-reachable definition is one of:
  - a function defined by pattern matching in a user module (including the
    auxiliary definitions Idris generates for `case`, `with` and `where`);
  - a data constructor of a profile data type;
  - a primitive allowed by `PROF-PRIM-*`;
  - a definition admitted by `PROF-LIB-1`.
  - Check: `Frontend.Profile.definitionKind`
  - Test: `tests/profile/v0/reject/PROF-FN-1-{extern,hole}.idr`
- **PROF-FN-2 (v0 only; replaced by PROF-FN-7).** Every function's type is a
  telescope ending in a runtime type, with as many binders as its case tree
  has arguments.
  - Test: `tests/profile/v0/reject/PROF-FN-2-returns-lambda.idr`
- **PROF-FN-3 (v0 only; replaced by PROF-FN-7).** No partial application.
  - Test: `tests/profile/v0/reject/PROF-FN-3-partial.idr`
- **PROF-FN-4 (v0 only; replaced by PROF-FN-7).** No lambda in a runtime
  position.
  - Test: `tests/profile/v0/reject/PROF-FN-4-lambda.idr`
- **PROF-FN-5 (v0).** Every runtime-reachable function is covering: not
  `partial`, and accepted by Idris's coverage check. Termination is not
  required.
  - Check: `Frontend.Profile.covering`
  - Test: `tests/profile/v0/reject/PROF-FN-5-partial.idr`,
    `tests/profile/v0/accept/PROF-FN-5-nonterminating.idr` (compile only)
- **PROF-FN-6 (v0).** Recursion, including mutual recursion, is allowed.
  - Test: `tests/profile/v0/accept/PROF-FN-6-{fib,mutual,tail-loop}.idr`
- **PROF-FN-7 (v1).** Higher-order functions, lambdas, partial application,
  functions returning functions, and polymorphic functions are allowed,
  subject to `PROF-HEAP-*` and `PROF-POLY-1`.
  - Test: `tests/profile/v1/accept/PROF-FN-7-{compose,twice,map-pair,state}.idr`
- **PROF-POLY-1 (v1).** Polymorphic recursion is rejected (`ELIM-MONO-3`).
  - Test: `tests/profile/v1/reject/PROF-POLY-1-nested.idr`

## Terms

- **PROF-TERM-1 (v0).** In runtime positions, these forms may appear:
  - local variables;
  - calls and constructor applications;
  - literals of runtime types;
  - allowed primitives;
  - `let` bindings;
  - pattern matching as compiled by Idris into case trees.

  From v1 also: lambdas, `Delay` and `Force` (other than `Inf`), and
  `%MkWorld`.
- **PROF-TERM-2 (v0).** In every version, these forms are forbidden in runtime
  positions:
  - `Type`;
  - metavariables and holes;
  - `Unmatched` case-tree leaves.

  In v0 only, `Delay`, `Force`, `%World` and IO are also forbidden.
  - Check: `Frontend.Translate`
  - Test: `tests/profile/v0/reject/PROF-TERM-2-{lazy,world,hole}.idr`

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
  - Test: `tests/e2e/v0/SEM-INT-*`
- **PROF-PRIM-2 (v0).** In every version, these primitives are rejected:
  - `prim__negate_T`, `prim__shl_T`, `prim__shr_T` (`SEM-EXCL-1`);
  - everything on `Integer` or `Double`;
  - `prim__believe_me` and `prim__crash`.

  In v0 only, primitives on `Char` and `String` are also rejected.
  - Test: `tests/profile/v0/reject/PROF-PRIM-2-{negate,shl,believe-me,crash}.idr`
- **PROF-PRIM-3 (v1).** The `Char` primitives are allowed:
  - `prim__lt_Char`, `prim__lte_Char`, `prim__eq_Char`, `prim__gte_Char`,
    `prim__gt_Char`;
  - `prim__cast_CharT` and `prim__cast_TChar`.

  Their meaning is `SEM-CHAR-*`.
  - Test: `tests/e2e/v1/SEM-CHAR-*`
- **PROF-PRIM-4 (v1).** Every `String` primitive may appear in the source.
  Each occurrence must be removed by compile-time evaluation or output fusion
  (`ELIM-G-6`, `ELIM-G-7`). A surviving string-building primitive is a
  `PROF-HEAP-3` error. Any other surviving string primitive (`strLength`,
  `strIndex`, string comparison, and so on) is rejected with this rule.
  - Test: `tests/profile/v1/reject/PROF-PRIM-4-runtime-length.idr`

## Heap freedom (v1)

These are checked on `Core` after the guaranteed eliminations
([06-elimination](06-elimination.md)). Each error points at the source
construct that survived, and says which elimination did not apply and why
(`DIAG-HEAP-1`).

- **PROF-HEAP-1 (v1).** No value of function type remains in a runtime
  position: no lambda, partial application, or function-typed parameter,
  field, `let` or result.
- **PROF-HEAP-2 (v1).** No `Lazy` value remains in a runtime position.
- **PROF-HEAP-3 (v1).** No string-building primitive remains (`strAppend`,
  `strCons`, `strReverse`, `strSubstr`, casts to `String`). So every runtime
  `String` value comes from a string literal, possibly passed through
  variables, arguments, fields and results, and lives in static data.
- **PROF-HEAP-4 (v1).** A recursive function does not pass itself a
  function-typed argument that differs from the one it received. This is
  Futhark's restriction that "a loop may not produce a function"; without it,
  specialization would not terminate.
- **PROF-HEAP-5 (v1).** Arity raising (`ELIM-G-5`) moves code only if that
  code cannot crash and cannot fail to terminate. A function that returns an
  action or function after such code cannot be raised, and its result
  survives as a function value; the error names the blocking operation.
  - Check: `Core.HeapCheck`, after `Simplify`
  - Test: `tests/profile/v1/reject/PROF-HEAP-{1..5}-*.idr`, and every v1
    accept fixture (the check passes)

## Escape hatches

- **PROF-ESC-1 (v0).** No reachable definition, at runtime or compile-time
  positions, may be or refer to any of:
  - `prim__believe_me` or `prim__crash`;
  - a definition marked as an escape hatch (`isEscapeHatch`);
  - a hole;
  - an `%extern` or `%foreign` definition other than those in `PROF-IO-2`.
  - Check: `Frontend.Profile.escapeHatches`
  - Test: `tests/profile/v0/reject/PROF-ESC-1-{believe-me-in-proof,hole-in-type}.idr`

  *Rationale:* the compiler trusts Idris's type checker for data layout and
  for impossible branches. An escape hatch in a proof can equate two
  different runtime types, and `replace` then reinterprets a value's
  layout. So the rule covers compile-time positions too.

## Pragmas

- **PROF-PRAG-1 (v0).** User modules contain no pragma. Every `%`-directive is
  forbidden, including `%default`. Fixity declarations (`infixl` and so on)
  are declarations, not pragmas, and are allowed.
  - Check: `Frontend.Profile.pragmas`. It lexes each user module's source with
    Idris's own lexer (`Parser.Lexer.Source`) and rejects every `Pragma`
    token at its position.
  - Test: `tests/profile/v0/reject/PROF-PRAG-1-{default,inline,transform}.idr`

  *Rationale:* pragmas change elaboration or code generation in ways the
  profile does not specify. Some leave traces in TT (`%inline`, `%transform`,
  `%spec`, `%foreign`); others leave none (`%default`, `%logging`). Lexing
  catches them all.

## Later versions (informative until adopted)

| Version | Adds |
| --- | --- |
| v2 | User-defined interfaces, whose dictionaries are eliminated by specialization; `do` over any user monad through a `Monad` interface; `Double` (with semantics added to 03 first) |
| v3 onward | The Prelude's dependency modules, one layer at a time and each fully tested: first the non-recursive parts of `Prelude.Basics`, `Prelude.Types`, `Prelude.Interfaces` and `Prelude.Ops` (`Bool`, `Maybe`, `Either`, `Num`/`Eq`/`Ord` at machine types) |
| after the memory design | recursive data, `Integer`, `Nat` at runtime, strings built at runtime, the stock Prelude imported implicitly |
