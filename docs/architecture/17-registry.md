# 17. The registry: privileged knowledge of library definitions

Every place the compiler treats a named Idris definition specially is an
entry of one registry: `IdrisMLIR.Registry` and the files under
`compiler/src/IdrisMLIR/Registry/`, one per category, and the library
table. The frontend's side of it, which turns Idris's names, modules and
types into the registry's and validates the entries, is
`IdrisMLIR.Frontend.Resolve`. This document is the normative list of the
entries; the code follows it.

## The principle

No language features in the compiler. Features are Idris libraries, and
the compiler has privileged knowledge of a fixed, registered set of them,
which it may make faster or stricter, but never different.
- Removing any hook may change speed or add a rejection. It never changes a
  program's result, and the Chez oracle is the check (`TEST-DIFF-1`).
- The compiler knows library definitions only through the registry.
  Nothing else in the codebase names an Idris definition (`HOOK-NAME-1`).

## Keys, shapes and hooks

An entry is data: the key the compiler knows a definition by, the shape it
expects the definition to have, its hook, and the rules the hook's handler
implements. The handler lives with the pass that meets the hook, not in the
registry.

- **Keys** are a closed sum:
  - `Def`: an Idris definition, by its qualified name;
  - `Foreign`: a `%foreign` spec as the libraries declare it for backends,
    a calling convention and a function, such as `C:idris2_putStr`. The spec
    is the backend contract; the Idris name that declares it and its type
    are the entry's shape;
  - `Spelling`: a spelling in the user's source, checked before TT exists.

  Idris's builtins are the closed type `PrimFn`, which the frontend matches
  directly, so they need no key.
- **Shapes** say what a definition's type must be: `Pi` with its quantity,
  `Head` (a definition applied to shapes), `Prim` (a primitive type),
  `TypeOfTypes`, and `Hole`, for a part the hook does not depend on (in a
  shape found, a part no shape describes, such as a variable). A shape is
  compared structurally with the definition's normalised checked type:
  arity, quantities and heads are exact. A fingerprint would not explain a
  mismatch, so there is none. One printer shows expected and found alike,
  in Idris's notation: `(0 _ : Type) -> (_ : PrimIO.IO _) -> _`.
- **Hooks** are a closed sum, one constructor per behaviour: `IOCall`,
  `IdentityOnLastArgument`, `ProgramRoot` and `Forbidden`. Passes match on
  the hook, never on a name, and Idris's coverage checker makes "every pass
  handles the hooks it can meet" structural.
- **Kinds.** A hook is `faster`, another lowering with the same meaning,
  or `stricter`, which adds a rejection. `kind` is a total function on
  hooks, so no hook can be mislabelled, and no other kind exists.

## Category 1: primitives

Idris's own backend contract (`Registry/Primitives.idr`). The compiler must
implement it; this is not privileged knowledge.

| Key | Declared by | Shape | Hook | Kind | Rules |
| --- | --- | --- | --- | --- | --- |
| `PrimIO.unsafePerformIO` | | `(0 _ : Type) -> (_ : PrimIO.IO _) -> _` | `ProgramRoot`: the term Idris hands an IO backend is `unsafePerformIO main`, written as world-passing code | faster | `FE-ENTRY-4` |
| `C:idris2_putStr` | `Prelude.IO.prim__putStr` | `(_ : String) -> (1 _ : %World) -> PrimIO.IORes Builtin.Unit` | `IOCall PutStr`: `idr.io.put_str` | faster | `PROF-IO-4` |
| `C:putchar` | `Prelude.IO.prim__putChar` | `(_ : Char) -> (1 _ : %World) -> PrimIO.IORes Builtin.Unit` | `IOCall PutChar`: `idr.io.put_char` | faster | `PROF-IO-4` |
| `C:getchar` | `Prelude.IO.prim__getChar` | `(1 _ : %World) -> PrimIO.IORes Char` | `IOCall GetByte`: `idr.io.get_byte` (`SEM-IO-7`) | faster | `PROF-IO-4` |

- Handlers: `ProgramRoot` in `Frontend.Main.compileIO`; `IOCall` in
  `Frontend.Translate.application`, and in `Frontend.Profile.checkReachable`,
  which lets a `%foreign` or `%extern` definition be reached only when it
  has one (`PROF-ESC-1`). An `%extern` definition would be keyed by its
  name; none is registered.
- Idris's entry convention is also category 1, as two functions rather
  than entries: the root of a `main : Int` program is `main` in its module
  (`PROF-PROG-2`), and a `main` without a module is taken from `Main`.
- *Coverage, not entries:* `Frontend.Translate.primitive` maps Idris's
  `PrimFn` to `Core` primitives (`PROF-PRIM-*`, `SEM-*`), and
  `BelieveMe` and `Crash` (`prim__believe_me`, `prim__crash`) are rejected
  where they are reached (`PROF-ESC-1`, `Frontend.Profile.checkReachable`).

## Category 2: recognized definitions

Ordinary library definitions the compiler treats specially
(`Registry/Recognized.idr`). This is the privileged-knowledge table.

| Key | Shape | Hook | Kind | Rules | Tests |
| --- | --- | --- | --- | --- | --- |
| `Builtin.replace` | `(0 _ : Type) -> (0 _ : _) -> (0 _ : _) -> (0 _ : _) -> (0 _ : Builtin.Equal _ _ _ _) -> (1 _ : _) -> _` | `IdentityOnLastArgument` | faster | `FE-TR-7` | `tests/registry/FE-TR-7-identity-hook`, `tests/e2e/v3/vect` |
| `Builtin.rewrite__impl` | as `replace` | `IdentityOnLastArgument` | faster | `FE-TR-7` | as `replace` |
| `PrimIO.unsafePerformIO` | as in category 1 | `Forbidden PROF-IO-3` | stricter | `PROF-IO-3` | `tests/profile/v1/reject/PROF-IO-3-unsafe-perform.idr` |
| `PrimIO.unsafeCreateWorld` | `(0 _ : Type) -> (1 _ : (1 _ : %World) -> _) -> _` | `Forbidden PROF-IO-3` | stricter | `PROF-IO-3` | private to `PrimIO`: a user module cannot name it |
| `PrimIO.unsafeDestroyWorld` | `(0 _ : Type) -> (1 _ : %World) -> (_ : _) -> _` | `Forbidden PROF-IO-3` | stricter | `PROF-IO-3` | as `unsafeCreateWorld` |
| spellings `prim__believe_me`, `prim__crash`, `believe_me`, `idris_crash` | | `Forbidden PROF-ESC-1` | stricter | `PROF-ESC-1` | `tests/profile/v0/reject/PROF-ESC-1-{believe-me,crash}.idr` |

- Handlers: `IdentityOnLastArgument` in `Frontend.Translate.application`;
  `Forbidden` on a definition in `Frontend.Profile.checkReachable` (a user
  definition that refers to it is rejected under the rule), and on a
  spelling in `Frontend.Profile.checkPragmas` (Idris evaluates
  `prim__believe_me` applied to a constructor while elaborating, so it can
  vanish from TT).
- Every recognized definition has a positive test showing its hook fires,
  or a rejection test showing its rule; every IO program is a differential
  test against Chez.

## Category 3: not hooks

Representation facts Idris computes itself are read from its metadata and
never registered by name. Name-based detection of something Idris already
flags is switched to the flag.
- `isEscapeHatch`, which `%unsafe` sets (`PROF-ESC-1`): `Builtin`'s
  `believe_me`, `idris_crash` and `assert_linear` are rejected on the flag,
  where a list of their names once excluded them from admission.
- `PrimType`, `TDelay`, `TForce` and `TDelayed`, `WorldVal`, and the
  `ZERO`/`SUCC` constructor flags (`Nat` is compile-time only, and nothing
  reads them yet).
- The compiler's own names are not Idris knowledge: instance names
  (`nameKey`), the `idris-mlir-binder` markers, the IO root
  `$idris-mlir.root`, and the structure of Idris's case and with blocks
  (`Frontend.Profile.enclosing`).

## The library table

Where code comes from is its *origin*: `User`, `Library` with one of
`Builtin`, `PrimIO`, `Prelude` and `Base` of an area (`Data`, `Control`,
`Decidable`, `Syntax`), or `Generated` (code in no module). The registry
computes it once, from the module Idris names, when TT is translated
(`Registry.Libraries.moduleOrigin`), and every location carries it, so the
origin flows through every IR and no pass reads a namespace.

What each purpose of the compiler makes of each library is one table,
purpose × library (`Registry/Libraries.idr`):

| Library | Trusted | Admitted | Inline hints | Break last | Report at caller |
| --- | --- | --- | --- | --- | --- |
| `Builtin` | yes | yes | yes | yes | yes |
| `PrimIO` | yes | only what it lists | yes | yes | yes |
| `Prelude` | yes | yes | yes | no | yes |
| base's areas | yes | yes | no | no | no |

`User` and `Generated` code is in no library.
- *Trusted*: an IO program may import the module, its source is not lexed,
  and its definitions must be admitted (`PROF-PROG-4`, `PROF-LIB-3`,
  `PROF-PRAG-1`, `PROF-LIB-1`).
- *Admitted*: every definition is admitted (`PROF-LIB-1`). `PrimIO` admits
  `IORes`, `MkIORes`, `PrimIO`, `IO`, `MkIO`, `prim__io_pure`, `io_pure`,
  `prim__io_bind`, `io_bind`, `fromPrim`, `toPrim`, `unsafePerformIO`,
  `unsafeCreateWorld` and `unsafeDestroyWorld`, and no other definition.
- *Inline hints*: `%inline` is the author's hint to unfold (`ELIM-G-19`).
- *Break last*: a function is chosen as a loop breaker only when its cycle
  has none from elsewhere (`OPT-PIPE-3`).
- *Report at caller*: a diagnostic inside is reported at the user's code
  that reached it (`DIAG-LOC-1`).
- A trusted library's own totality assertions (`Builtin.assert_total`,
  an escape hatch that changes no value) are trusted (`PROF-ESC-1`); the
  user's are rejected on Idris's flag.

The table keeps the membership of the lists it replaced, so their
disagreements are its cells, recorded here for a later decision:
- only *Trusted* and *Admitted* cover base;
- *Break last* leaves out the Prelude;
- base is recognized by namespace, as every list did: a module of another
  package under `Data`, or a user module named so, is base, although
  `PROF-LIB-3` speaks of the base library alone;
- classifying by the module a location is in, where some lists read a
  definition's name, makes a namespace nested in a library module (`DPair`
  in `Builtin`) that library's code, as `PROF-LIB-1`'s table says, and the
  module names that *Report at caller* once matched in both orientations
  are read once, outermost first. No program reaches either difference.

## Validation

- **HOOK-SHAPE-1 (v3).** At the start of every compilation, before anything
  uses the registry, each entry with a definition (keys `Def` and
  `Foreign`) is resolved once against the loaded context.
  - An entry whose module the program does not load is not checked.
  - A definition missing from its loaded module, a definition that does
    not declare its entry's `%foreign` spec, and a definition whose
    normalised checked type does not conform to its entry's shape are each
    rejected: `unsupported (HOOK-SHAPE-1)`, naming the entry, the shape
    expected and the shape found, through one printer. So is a `%foreign`
    definition that declares an entry's spec under another name, where it
    is reached.
  - There is never a silent fallback to the generic path: that would be a
    hidden performance cliff.
  - *Test hook:* `--directive break-shape=<key>` gives the entry shown as
    `<key>` (`Builtin.replace`, `C:idris2_putStr`) one more argument in
    front, `(_ : %World)`, which no entry's definition takes, so that entry
    fails. A key that names no entry with a definition is an internal
    error.
  - Check: `Frontend.Resolve.validate`, run by `Frontend.Main.compileModule`
    and `Frontend.Main.compileIO`
  - Test: `tests/registry/HOOK-SHAPE-1-broken-entry`

## No names outside the registry

- **HOOK-NAME-1 (v3).** Outside `IdrisMLIR.Registry` and the files under
  `Registry/`, no string literal in `compiler/src` or in the dialect's
  sources under `foreign/idr` is a qualified Idris name or a namespace the
  library table classifies, and no Idris name is built from a literal.
  - Passes ask the registry with a key and match on the hook it returns.
  - Idris names reach the middle end as `Shown`, which can be printed but
    not compared (it has `Show` and no `Eq`): `Data`, `TFn`, `CData` and
    `CFn` carry one, and M2's old name test is an origin test.
  - They reach MLIR as locations (`IDR-DATA-5`).
  - An allowlist names the lines allowed anyway, each with its reason; it
    is empty.
  - Check: the golden test, which greps `compiler/src` and `foreign/idr`
  - Test: `tests/registry/HOOK-NAME-1-registry-only`

## Facts

A hook's results, like Idris's own analyses, become facts about functions,
each recorded with its provenance (`IdrisMLIR.Facts`; [the
plan](../plan.md), section 8.3). The record today holds whether a function
terminates (Idris's totality checker), whether it is a case or with block
(the structure of Idris's names), and whether it is unfolded as its
author's `%inline` hint (the library table). The IO root is the
`ProgramRoot` hook's code, so its facts are the registry's. Rules consume
facts whatever their provenance.

## The C++ boundary

- Idris names end at the frontend. The `idr` dialect and every C++ pass see
  ops, types and attributes, never an Idris name.
- In MLIR an Idris name is a location: `idr.data`, `idr.ctor` and
  `func.func` are located by a `NameLoc` holding it (`IDR-DATA-5`). Names
  are debug information, which MLIR passes keep and diagnostics print; the
  dialect has no attribute that holds a name, so C++ cannot compare one.
- C++ that would need an Idris name has that knowledge moved into the
  registry, and `Emit` produces a dedicated op or attribute instead.
- The extern symbols the runtime implements stay in one C++ table, the
  `Idr_Helper` traits of `IdrOps.td`, which category 1 mirrors: each
  `IOCall` hook names an `idr.io` op, and each such op its helper. The two
  are kept in agreement by review; no test checks it yet.

## Adding a hook

A new `faster` or `stricter` behaviour is a constructor of `Hook` (with its
kind), an entry in the table of its category with its key, shape and
rules, and a handler in the pass that meets it, with a positive or a
rejection test. Nothing else in the compiler changes.
