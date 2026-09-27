# 04. Frontend: reading checked TT

The frontend is the Idris code under `IdrisMLIR.Frontend.*`. It is the only
code that imports upstream Idris compiler modules. It turns the checked
program into `Core` ([05-middle-ir](05-middle-ir.md)) and reports every
profile violation that TT can show.

## Registration and entry (v0)

- **FE-ENTRY-1 (v0).** The executable `idris-mlir` is the stock Idris 2
  driver with one backend, `mlir`, registered through `mainWithCodegens`.
  It accepts every stock Idris option.
- **FE-ENTRY-2 (v0).** In v0 a program compiles through the incremental
  callback (`incCompileFile`):

  ```sh
  idris-mlir --no-prelude --cg mlir --inc mlir --check Prog.idr
  ```

  Idris calls the callback after it has checked the module and before it
  writes the module's TTC. The callback compiles the whole program starting
  from the root.
- **FE-ENTRY-3 (v0 only; replaced by FE-ENTRY-4).** The whole-program
  callback (`compileExpr`, used by `-o`) fails with an `unsupported` error,
  because it receives `unsafePerformIO main` and v0 has no IO.
  - Test: `tests/compiler` (the existing rejection test)
- **FE-ENTRY-4 (v1).** IO programs compile through the whole-program callback:

  ```sh
  idris-mlir --no-prelude -p idris-mlir-io --cg mlir -o prog Main.idr
  ```

  - The callback receives the closed term `unsafePerformIO main` and the
    `Defs` of every loaded module.
  - The term MUST be exactly that application, with `main : IO ()` in the
    main module; anything else is a `PROF-PROG-4` error. `main` is the root.
  - The callback then runs the whole driver chain (`DRV-FLOW-2`).
- **FE-ENTRY-5 (v1).** `--exec` is not supported and fails with an
  `unsupported` error naming `FE-ENTRY-5`.

## What the frontend reads

- **FE-IN-1 (v0).** The frontend reads:
  - **from `Defs`:** definitions via `lookupCtxtExact`, and `imported`;
  - **from each `GlobalDef`:** `type`, `definition` (`PMDef` args and
    `treeCT`, `DCon`, `TCon`, `Builtin`, `Hole`, `ExternDef`, `ForeignDef`),
    `multiplicity`, `totality`, `isEscapeHatch`, `flags`, `location`, and
    `fullname`;
  - **the source file of each user module**, only to lex it for pragmas,
    hole identifiers and escape-hatch names (`PROF-PRAG-1`, `PROF-ESC-1`),
    and to find its `import` lines for error locations (`PROF-PROG-1`,
    `PROF-PROG-4`). User modules are those not listed in `PROF-LIB-1`.
  - Check: review (what the frontend reads)
- **FE-IN-2 (v0).** The frontend MUST NOT read:
  - `treeRT`, `compexpr`, `namedcompexpr` or `schemeExpr`;
  - any `CExp`, `NamedCExp`, `Lifted`, `ANF` or `VM` form;
  - `getCompileData` or `getIncCompileData`.

  These have already erased facts, or were built for other backends.
  - Check: review, plus a tooling test that greps `compiler/src` for these
    names
  - Test: `tests/tooling/test_dev.py`
- **FE-IN-3 (v0).** Only modules named `IdrisMLIR.Frontend.*` import
  upstream Idris compiler modules.
  - Check and test: the existing import-boundary tooling test
- **FE-IN-4 (v0).** Idris's `eraseArgs` and `safeErase` fields are not used
  to decide runtime positions. A position is compile-time exactly when its
  binder in the callee's or constructor's type has quantity 0.
  - *Rationale:* `safeErase` also contains positions that Idris erased by
    collapsibility analysis. v0 does not rely on that analysis
    ([06-elimination](06-elimination.md) may adopt it later, as a fact).
  - Check: review (`Frontend.Translate.classify` decides runtime positions from quantities)

## Stages

Both callbacks run these stages in order and stop at the first error. Each
error follows `DIAG-*`.

1. **Pragmas (`PROF-PRAG-1`).** Lex each user module's source with
   `Parser.Lexer.Source.lex` and reject every `Pragma` token, at its bounds.
2. **Program shape.**
   - For `main : Int` (`PROF-PROG-1`): `imported` is empty. Each entry is an
     error at the module. p0 verifies that `--no-prelude` records no implicit
     entry. If the pinned Idris does record one, this rule is amended to name
     it, rather than the check silently allowing it.
   - For `main : IO ()` (`PROF-PROG-4`): every imported module is a user
     module or a trusted module.
3. **Root.**
   - For `main : Int` (`PROF-PROG-2`): resolve `NS <module> (UN (Basic "main"))`.
     Its normalized type must be `Int`, and its definition a `PMDef` with
     zero arguments.
   - For IO programs, the root comes from `FE-ENTRY-4`.
4. **Reachability (`FE-REACH-1`).**
5. **Profile checks on TT:** `PROF-ESC-1`, `PROF-LIB-*`, `PROF-IO-3`,
   `PROF-FN-1`, `PROF-FN-5`, `PROF-DATA-*` (and, in v0, `PROF-FN-2`).
6. **Translation to full `Core` (`FE-TR-*`)**, which also checks
   `PROF-TERM-*` and `PROF-PRIM-*` (and, in v0, `PROF-TYPE-2`, `PROF-FN-3`
   and `PROF-FN-4`).
7. **The middle end** (`Mono`, `Simplify`) **and emission**
   ([05-middle-ir](05-middle-ir.md)).
8. **Artifacts (`FE-ART-1`)**, then, for IO programs, the rest of the driver
   chain (`DRV-FLOW-2`).

- **FE-REACH-1 (v0).** Reachability is a worklist from the root over every
  name referenced by a definition's `type` and `treeCT`, including names in
  compile-time positions. Visiting order is deterministic (`FE-DET-1`).
  Definitions reached only through compile-time positions are checked
  against `PROF-ESC-1` and are not translated.
- **FE-TOT-1 (v0).** Coverage status comes from Idris's totality checker
  (`Core.Termination.checkTotal`), not from a `totality` field that may be
  unchecked.
  - Test: `tests/profile/v0/reject/PROF-FN-5-partial.idr`

## Translation to Core

- **FE-TR-1 (v0). Types.** The type of every runtime binder is normalized with
  Idris's normalizer (`Core.Normalise.normalise`) in its environment. The
  result MUST be one of:
  - a primitive type constant in `PROF-TYPE-1`;
  - a type constructor (`Ref` to a `TCon`) with no arguments that satisfies
    `PROF-DATA-*`.

  From v1, the result may also be:
  - `Char`, `String` or `%World`;
  - a type constructor applied to its parameters;
  - a function type or `Lazy`.

  Anything else is a `PROF-TYPE-2` error (v0) or a `PROF-TYPE-4` error (v1)
  at the binder's location.

  TTC does not store the types of `let` binders (`Core.TTC` writes only the
  value), so under `-o` a runtime `let` has type `Erased` in TT. Full `Core`
  therefore has no let types (`05-middle-ir`): `Simplify` knows the type of
  a let-bound value when it evaluates it.
- **FE-TR-2 (v0). Quantities.** Each Pi binder's quantity maps to `Q0`, `Q1`
  or `QW`. The quantity is recorded on every parameter, every constructor
  field, and every `let` in `Core` (`CORE-INV-4`).
- **FE-TR-3 (v0). Terms.** Each runtime-position term translates as follows:

  | TT | Core |
  | --- | --- |
  | `Local` | variable |
  | `Ref` to a `PMDef`, saturated | call |
  | `Ref` to a `DCon`, saturated | constructor application |
  | `Ref` to an allowed `Builtin`, saturated | primitive |
  | `PrimVal` of a runtime type | literal (`SEM-LIT-1`) |
  | `Bind` with `Let` | `let` with its quantity |
  | `Bind` with `Lam` (v1) | `Lam`, closure-converted: a fresh label, its captured variables, and its body closed over them |
  | unsaturated or over-saturated application (v1) | `App` and `Lam` (eta-expansion), with the call saturated where the arity is known |
  | `TDelay` / `TForce` with reason `LLazy` (v1) | `Delay` (closure-converted like `Lam`) / `Force` |
  | `PrimVal` of `Char` or `String` (v1) | literal |
  | `PrimVal WorldVal` (`%MkWorld`) (v1) | `PROF-IO-3` error: the root is written without it (`FE-ENTRY-4`) |
  | `Ref` to a `PROF-IO-2` primitive (v1) | IO primitive (`Effect`) |
  | `Meta`, `TDelay`/`TForce` with reason `LInf`, `Bind` with `Pi`, `TType`, anything else | `unsupported` error with the matching rule |

  - Arguments in compile-time positions become the `Core` erased value,
    whatever their TT form.
- **FE-TR-4 (v0). Case trees.**

  | `CaseTree` / `CaseAlt` | Core |
  | --- | --- |
  | `Case` on a variable | match on that variable |
  | `ConCase` | alternative with the constructor's tag, binding its fields (compile-time fields bind the erased value) |
  | `ConstCase` on an integer or `Char` constant | literal alternative (a `ConstCase` on `String` is a `PROF-PRIM-4` error) |
  | `DefaultCase` | default alternative |
  | `DelayCase` | `PROF-TERM-2` error |
  | `STerm` | term |
  | `Unmatched` | `Unreachable`: the definition is covering (`PROF-FN-5`), so Idris proved no input reaches it. A definition whose clauses are all `impossible` is one such leaf. |
  | `Impossible` | `Unreachable` (`SEM-DATA-2`) |

  A constructor match without a default that leaves out constructors gets
  an `Unreachable` alternative for each of them: the definition is covering
  (`PROF-FN-5`), so Idris proved them impossible. Every constructor match is
  therefore exhaustive (`CORE-INV-6`).

- **FE-TR-5 (v1). Polymorphism.** Before `Mono`, the type of a runtime binder
  may contain the definition's quantity-0 type parameters, which become
  `TyVar`. The closedness check of `FE-TR-1` then runs after `Mono`
  (`PROF-TYPE-4`).
- **FE-TR-6 (v2). Implementations are compile-time values.** An interface
  is a single-constructor data type whose fields are the superclass
  implementations and the methods; a method with type variables of its own
  has a polymorphic type, which no `Core` type describes. Idris resolves
  every constraint at compile time, so the frontend treats implementations
  like type arguments:
  - An argument in an auto-implicit position of runtime quantity, an
    argument that is a variable bound to an implementation, or an argument
    whose parameter's type is an interface (as Idris passes constraints to
    `where` functions and case and with blocks, explicitly; an interface's
    record is declared with unique search) is a compile-time value: the
    closed TT term as written, with the enclosing compile-time values
    substituted and not normalised, except that its outer `let`s are
    substituted: Idris elaborates a record update to a `let` of the record,
    and an implementation resolved inside it is written under that `let`
    without using it. Solved metavariables left in it are filled in (from
    v3: the implementation for the inner pair of a triple). A lambda over
    an implementation (a dictionary's polymorphic method field,
    `\@{m} => ...`) takes it as written, like a type. It keys the instance
    (`ELIM-MONO-1`) and is erased at runtime.
    - Test: `tests/e2e/v2/nbody` (record updates that use `negate` and `*`)
  - An argument that depends on a runtime value is rejected: an
    implementation chosen at runtime (`PROF-HEAP-1`).
  - A match on an implementation selects its alternative during
    translation. The implementation is reduced to its constructor by
    unfolding definitions that are one right-hand side (every
    implementation is), and by Idris's normaliser otherwise.
  - A method applied to its type arguments is substituted with them before
    it is translated, so it is translated at the types of each use.

  No dictionary exists in `Core`; each method call is an ordinary call of a
  monomorphic instance, which `ELIM-G-3` specializes like any other.
  - Test: `tests/e2e/v2/interface-*`,
    `tests/profile/v2/accept/FE-TR-6-named-implementations.idr`,
    `tests/profile/v2/reject/PROF-HEAP-1-runtime-implementation.idr`
- **FE-LOC-1 (v0).** Every `Core` definition carries its `GlobalDef`
  location. Every `Core` term carries the `FC` of the TT node it came from,
  or else its definition's location. The MLIR emitted for it carries the same
  location (`IDR-LOC-1`).
- **FE-DET-1 (v0).** The same input produces byte-identical `.core` and
  `.mlir` files. Definitions are visited in a deterministic order: worklist
  order from the root, ties broken by full name.
  - Test: `tests/e2e/v0/determinism` (compile twice and compare)

## Artifacts (v0)

- **FE-ART-1 (v0).** On success, the frontend writes the printed `Core`
  (`.core`) and the contract text (`.mlir`), and on failure writes neither
  and removes any stale copies:
  - **`main : Int`:** the incremental callback writes `<Module>.core` and
    `<Module>.mlir` next to the module's TTC, and returns the `.mlir` path to
    Idris as its object file.
  - **IO programs:** the whole-program callback writes `<prog>.core` and
    `<prog>.mlir` in Idris's output directory (`build/exec/` by default),
    then continues with `DRV-FLOW-2`.
  - Test: every reject fixture asserts that neither file exists
    (`TEST-REJ-1`)

## Idris facts and their limits (informative)

| Fact | Where it is | Survives TTC |
| --- | --- | --- |
| Binder quantities | `type` (Pi binders), `multiplicity` | Only for user names (`isUserName`) |
| Compile-time case tree | `PMDef … treeCT` | Yes |
| Runtime case tree | `PMDef … treeRT` | No (and never read) |
| Constructor tag, arity, newtype argument | `DCon` | Yes |
| Parameters, detaggable positions | `TCon` | Yes |
| Totality | `totality`, and computed by the checker | Only for user names |
| `let` binder types | `Bind … (Let _ _ val ty)` | No: `ty` becomes `Erased` (`FE-TR-1`) |
| Term locations (`FC`) | every `Term` constructor | No: only definition locations survive (`DIAG-LOC-1`) |
| Escape hatch | `isEscapeHatch` | Only for user names |

`isUserName` is false for `MN` and `PV` names. After a TTC round trip, such
definitions have type `Erased` and no totality.
- **FE-TTC-1 (v1).** If a needed fact is missing from an imported
  definition, the frontend MUST fail with `unsupported`, naming the
  definition. It MUST NOT guess.
  - Check: review (`Frontend.Translate.lookupDef` rejects a missing definition; a TTC missing a fact cannot be produced by the pinned Idris)

## Imported modules (v1)

- **FE-TTC-2 (v1).** Under `-o`, Idris loads modules from TTC, including the
  trusted modules. So `FE-TTC-1` applies to every definition the program
  reaches. v1's entry criterion (`RM-V1-1`) is an experiment confirming that
  every definition admitted by `PROF-LIB-1`, and the definitions Idris
  generates for ordinary user code, keep the facts the frontend needs.
  Anything missing is rejected, never guessed.
