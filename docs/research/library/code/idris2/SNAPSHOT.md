# Snapshot: Idris 2 compiler sources

- **Upstream:** `idris-lang/Idris2`, at the pin of this repository's `third_party/Idris2`
  submodule.
- **Revision:** `1c630e67c386629a0fbbc6b78a59176fde7f0a76` (pinned commit `1c630e67`,
  `v0.7.0-551-g1c630e67c`).
- **Fetched:** 2026-09-26, from
  `https://raw.githubusercontent.com/idris-lang/Idris2/1c630e67c386629a0fbbc6b78a59176fde7f0a76/<path>`.
  The local `third_party/Idris2` checkout was empty then, so the pinned raw URLs were used.
- **Paths:** relative to the Idris2 repository root (so `src/Core/...`).
- **Files:** 30.
- **Licence:** BSD-3-Clause (verify).
- **Threads:** E, D, I, cross-cutting.

**What is here.**
- `src/Core/`: `TT.idr`, `TT/Term.idr`, `TT/Binder.idr`, `Case/CaseTree.idr`,
  `Case/CaseBuilder.idr`, `Case/Util.idr`, `Context/Context.idr`, `LinearCheck.idr`,
  `CompileExpr.idr`, `Transform.idr`.
- `src/Compiler/`: `CompileExpr.idr`, `Inline.idr`, `ANF.idr`, `LambdaLift.idr`,
  `CaseOpts.idr`, `VMCode.idr`, `Interpreter/VMCode.idr`, `RefC.idr`, `RefC/RefC.idr`,
  `RefC/CC.idr`, `Scheme/{Chez,ChezSep,Common,Gambit,Racket}.idr`.
- `src/TTImp/`: `TTImp.idr`, `TTImp/{Functor,TTC,Traversals}.idr`, `ProcessTransform.idr`.

**What the manifest asked for.** `src/Core/TT.idr`, `Core/TTImp/*`,
`Core/Context/Context.idr`, `Core/Case/CaseTree.idr`, `Compiler/CompileExpr.idr`,
`Compiler/Erase.idr` (verify path), `Compiler/Inline.idr`, `Compiler/ANF.idr`,
`Compiler/LambdaLift.idr`, `Compiler/CaseOpt.idr`, the RefC/Scheme/VM backends, and the
`detagabbleBy` and Nat/newtype handling. For Thread I it also asked for the `%transform`
and totality material: `src/Core/Transform.idr` and `src/TTImp/ProcessTransform.idr` are
here; the adjacent `src/Core/Termination/*` was not separately copied.

**Corrections.**
- `TTImp` is `src/TTImp/**`, not `src/Core/TTImp/**`.
- There is no `Compiler/Erase.idr`. Erasure lives in `src/Core/LinearCheck.idr`
  (multiplicity/erasure inference with `Erased` nodes) plus the `eraseArgs` / `safeErase`
  fields of `GlobalDef` in `src/Core/Context/Context.idr`.
- Idris 2 case optimization is `src/Compiler/CaseOpts.idr`, not `CaseOpt.idr`.

**Not collected.** Idris `Integer`/`String` sources and the `Vect`/index-typed array
material were planned and not taken (see the library [README](../../README.md#planned-sources-not-collected)).
The submodule is checked out now, so `third_party/Idris2` can be read in place at the same
revision.
