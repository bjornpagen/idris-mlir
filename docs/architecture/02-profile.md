# 02. The profile: a strict subset of Idris 2

**Contract document.** Changes need the user's approval
([00-index](00-index.md#change-process)).

The profile is the part of Idris 2 this compiler accepts. It selects
constructs and adds nothing. This document defines profile **v0** normatively.
Later versions are sketched at the end and become normative only when adopted.

## General rules

- **PROF-GEN-1 (v0).** Every program in the profile is an ordinary Idris 2
  program. The pinned stock Idris accepts it, and it means what
  [03-semantics](03-semantics.md) says, which agrees with stock Idris.
- **PROF-GEN-2 (v0).** Every rule in this document is enforced by the
  compiler. A violation fails compilation with an `unsupported` error that
  names the rule and points at the Idris source ([13-diagnostics](13-diagnostics.md)).
- **PROF-GEN-3 (v0).** Rules are stated at source level but checked on
  checked TT, because elaboration inserts implicit arguments, auto-bound
  names and generated definitions that the source does not show. Where source
  and TT disagree, the check on TT decides.
- **PROF-GEN-4 (v0).** Each version is a superset of the previous version,
  and adopting a new version changes the meaning of no program already in the
  profile.

Scope of the rules:
- **Reachable** means reachable from the root through any reference in types
  or bodies, at runtime or compile-time positions.
- **Runtime-reachable** means reachable through runtime positions only (see
  the [glossary](00-index.md#glossary)).

Unless a rule says otherwise, it applies to runtime-reachable definitions.

## Program shape (v0)

- **PROF-PROG-1 (v0).** A program is exactly one Idris source file, compiled
  with `--no-prelude`. It has no `import` declarations.
  - Check: `Frontend.Profile.programShape`
  - Test: `tests/profile/v0/reject/PROF-PROG-1-import.idr`
- **PROF-PROG-2 (v0).** The module defines `main : Int`, with no arguments.
  `main` is the root.
  - Check: `Frontend.Roots.findRoot`
  - Test: `tests/profile/v0/reject/PROF-PROG-2-{missing,io,args}.idr`
- **PROF-PROG-3 (v0).** Definitions that are not reachable are neither
  checked nor compiled. They remain subject to `PROF-PRAG-1`, which applies to
  the whole file.

*Note:* conformance fixtures state the expected results as Idris proofs
(`check : Prog.main = 42; check = Refl`) in a separate oracle file that
imports `Builtin` and the program. That file is checked by stock Idris and is
not compiled by this compiler ([14-testing](14-testing.md)).

## Runtime types (v0)

- **PROF-TYPE-1 (v0).** The runtime types of v0 are:
  - `Int`, `Int8`, `Int16`, `Int32`, `Int64`;
  - `Bits8`, `Bits16`, `Bits32`, `Bits64`;
  - profile data types (`PROF-DATA-*`).
- **PROF-TYPE-2 (v0).** The type of every runtime position MUST normalize, by
  Idris's own normalizer in its context, to a closed runtime type. This
  excludes at runtime:
  - `Integer`, `Double`, `Char`, `String`, `%World`;
  - `Type` and other universes;
  - function types;
  - `Lazy` and `Inf`;
  - types containing free variables (polymorphism);
  - types that depend on runtime values.
  - Check: `Frontend.Profile.runtimeType`
  - Test: `tests/profile/v0/reject/PROF-TYPE-2-{integer,double,char,string,type,function,poly,dependent}.idr`
- **PROF-TYPE-3 (v0).** Compile-time positions (quantity 0) may have any type
  that stock Idris accepts, subject to `PROF-ESC-1`.
  - Test: `tests/profile/v0/accept/PROF-TYPE-3-erased-witness.idr`

## Data types (v0)

- **PROF-DATA-1 (v0).** A data type used at a runtime position is declared in
  the program's module, and its type constructor has type `Type`: no
  parameters and no indices. Records are data types.
  - Check: `Frontend.Profile.dataDecl`
  - Test: `tests/profile/v0/reject/PROF-DATA-1-{param,index}.idr`
- **PROF-DATA-2 (v0).** Every constructor field in a runtime position has a
  runtime type. Fields with quantity 0 may have any type.
  - Check: `Frontend.Profile.dataDecl`
  - Test: `tests/profile/v0/reject/PROF-DATA-2-integer-field.idr`,
    `tests/profile/v0/accept/PROF-DATA-2-erased-field.idr`
- **PROF-DATA-3 (v0).** Runtime data types are not recursive. In the graph
  with an edge T → U whenever a constructor of T has a runtime field of
  type U, no cycle is reachable from a runtime data type. Quantity-0 fields
  add no edges.
  - Check: `Frontend.Profile.dataDecl`, and the dialect verifier `IDR-DATA-4`
  - Test: `tests/profile/v0/reject/PROF-DATA-3-{list,mutual}.idr`
- **PROF-DATA-4 (v0).** Data types with zero constructors are allowed. Their
  values cannot exist at runtime.
  - Test: `tests/profile/v0/accept/PROF-DATA-4-void.idr`

## Functions (v0)

- **PROF-FN-1 (v0).** Every runtime-reachable definition is one of:
  - a function defined by pattern matching in the program's module (including
    the auxiliary definitions Idris generates for `case`, `with` and `where`);
  - a data constructor of a profile data type;
  - a primitive allowed by `PROF-PRIM-1`.
  - Check: `Frontend.Profile.definitionKind`
  - Test: `tests/profile/v0/reject/PROF-FN-1-{extern,hole}.idr`
- **PROF-FN-2 (v0).** Functions are first order.
  - Every function's type is a telescope of binders ending in a runtime
    type.
  - The number of binders equals the number of arguments of its case tree:
    no definition returns a lambda.
  - Check: `Frontend.Profile.signature`
  - Test: `tests/profile/v0/reject/PROF-FN-2-returns-lambda.idr`
- **PROF-FN-3 (v0).** Every runtime call supplies all of the callee's
  arguments. There is no partial application.
  - Check: `Frontend.Translate`
  - Test: `tests/profile/v0/reject/PROF-FN-3-partial.idr`
- **PROF-FN-4 (v0).** No lambda (`\x => …`) appears in a runtime position.
  - Check: `Frontend.Translate`
  - Test: `tests/profile/v0/reject/PROF-FN-4-lambda.idr`
- **PROF-FN-5 (v0).** Every runtime-reachable function is covering: it is
  not `partial`, and Idris's coverage check accepts it. Termination is not
  required.
  - Check: `Frontend.Profile.covering`
  - Test: `tests/profile/v0/reject/PROF-FN-5-partial.idr`,
    `tests/profile/v0/accept/PROF-FN-5-nonterminating.idr` (compile only;
    the test does not run the program)
- **PROF-FN-6 (v0).** Recursion, including mutual recursion, is allowed.
  - Test: `tests/profile/v0/accept/PROF-FN-6-{fib,mutual,tail-loop}.idr`

## Terms (v0)

- **PROF-TERM-1 (v0).** In runtime positions, only these forms may appear:
  - local variables;
  - saturated calls;
  - saturated constructor applications;
  - integer literals of runtime types;
  - allowed primitives;
  - `let` bindings;
  - pattern matching on constructors or integer literals, as compiled by
    Idris into case trees.
- **PROF-TERM-2 (v0).** These forms are forbidden in runtime positions:
  - `Delay` and `Force`;
  - `%World` and IO;
  - `Type`;
  - metavariables and holes;
  - `Unmatched` case-tree leaves (which only partial definitions produce).
  - Check: `Frontend.Translate`
  - Test: `tests/profile/v0/reject/PROF-TERM-2-{lazy,world,hole}.idr`

## Primitives (v0)

For each `T` in {`Int`, `Int8`, `Int16`, `Int32`, `Int64`, `Bits8`, `Bits16`,
`Bits32`, `Bits64`}:

- **PROF-PRIM-1 (v0).** The allowed primitives are:
  - `prim__add_T`, `prim__sub_T`, `prim__mul_T`;
  - `prim__div_T`, `prim__mod_T`;
  - `prim__and_T`, `prim__or_T`, `prim__xor_T`;
  - `prim__lt_T`, `prim__lte_T`, `prim__eq_T`, `prim__gte_T`, `prim__gt_T`;
  - `prim__cast_ST` for every pair of distinct `S` and `T` in the set.

  Their meaning is fixed by `SEM-INT-*`.
  - Check: `Frontend.Translate.primitive`
  - Test: `tests/e2e/v0/SEM-INT-*.idr`
- **PROF-PRIM-2 (v0).** All other primitives are rejected, in particular:
  - `prim__negate_T`, `prim__shl_T`, `prim__shr_T` (see `SEM-EXCL-1`);
  - everything on `Integer`, `Double`, `Char` or `String`;
  - `prim__believe_me` and `prim__crash`.
  - Check: `Frontend.Translate.primitive`
  - Test: `tests/profile/v0/reject/PROF-PRIM-2-{negate,shl,believe-me,crash}.idr`

## Escape hatches (v0)

- **PROF-ESC-1 (v0).** No reachable definition, at runtime or compile-time
  positions, may be or refer to any of:
  - `prim__believe_me` or `prim__crash`;
  - a definition marked as an escape hatch (`isEscapeHatch`);
  - a hole;
  - an `%extern` or `%foreign` definition.
  - Check: `Frontend.Profile.escapeHatches`
  - Test: `tests/profile/v0/reject/PROF-ESC-1-{believe-me-in-proof,hole-in-type}.idr`

  *Rationale:* the compiler trusts Idris's type checker for data layout and
  for impossible branches. An escape hatch in a proof can equate two
  different runtime types, and `replace` then reinterprets a value's
  layout. So the rule covers compile-time positions too.

## Pragmas (v0)

- **PROF-PRAG-1 (v0).** The source file contains no pragma. Every
  `%`-directive is forbidden, including `%default`.
  - Check: `Frontend.Profile.pragmas`. It lexes the source file with Idris's
    own lexer (`Parser.Lexer.Source`) and rejects every `Pragma` token at
    its position.
  - Test: `tests/profile/v0/reject/PROF-PRAG-1-{default,inline,transform}.idr`

  *Rationale:* pragmas change elaboration or code generation in ways the
  profile does not specify. Some leave traces in TT (`%inline`, `%transform`,
  `%spec`, `%foreign`); others leave none (`%default`, `%logging`). Lexing
  catches them all.

## Later versions (informative until adopted)

| Version | Adds | Needs |
| --- | --- | --- |
| v1 | Several modules (user modules only); parametric data types and polymorphic functions over runtime types; `Double` and `Char` at runtime, with semantics added to 03 first | monomorphisation ([06](06-elimination.md)); the multi-module decision (open question 1) |
| v2 | Statically known higher-order functions (lambdas, partial application, function arguments), within restrictions like Futhark's; user-defined interfaces | defunctionalisation ([06](06-elimination.md)) |
| v3 | `main : IO ()` and a fixed IO surface | world-token erasure; the IO decision (open question 2) |
| v4 | A trusted part of the Prelude (`Num`, `Eq`, `Ord` at machine types); `Vect n a` with a static `n` | Prelude trust (open question 3); index-driven layout |

Recursive data, `Integer`, `Nat` at runtime, `String` and laziness stay
outside the profile until the memory design exists.
