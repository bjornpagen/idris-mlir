<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Contract: the specification's Core vocabulary and the pass list

Written by L03, on disk under `compiler/spec/IdrisMLIR/Spec/Core/` and
`Spec/Pipeline/`, 2026-10-21. Every lane writing under `compiler/spec/`
and every lane with a pass writes against it.

**1. Imports.** `IdrisMLIR.Spec.Core` is a directory, not a module.
Import `IdrisMLIR.Spec.Core.Vocabulary`, which re-exports all of Core
plus `Spec.Pipeline.Stage`. Or import single modules: Core.Text,
Core.Dialect, Core.Hooks, Core.Enums, Core.Cpp, Core.Upstream,
Core.Interfaces, Core.Types, Core.Constraints, Core.Format, Core.Ods,
Core.Admitted, Core.Op, Core.Rewrite, Core.Rules, Core.Declarations.
`design/one-source.md` §4.2's sketch API (an unindexed `Op` with `ins :
List Operand`, `family`, `leaves`, `CodecP`, `MkFormatHook`, `CppTable`)
is not Core's. Write against Core as it is.

**2. Text is typed,** and ASCII by an erased proof, with literal syntax:
- `"str.length" : Mnemonic`
- `"Graded" : Ident`
- `"summary" : Line`
- `"a\nb" : Prose`
- `"str_length" : Symbol`, which prints `idris_rt_str_length`
- `"::mlir::Type" : Code`
- `Doc = MkDoc Line Prose`

**3. An op (C75) is `Op i o a r`,** indexed by its operand, result,
attribute and region group counts. Its fields: `home`, `mnemonic`,
`ins : Vect i Operand`, `outs : Vect o Result`, `attrs : Vect a Attr`,
`regions : Vect r Region`, `traits : List (Trait i o)`,
`interfaces : List InterfaceUse`, `effects : Declaration i o`,
`speculation`, `stages : Legal`, `meaning : Meaning i o`, `verify`,
`format : Format i o a r`, `builders`, `defaultBuilders`, `members`,
`guards : List (Guard i)`, `specializations`, `laws`, `doc`.
- Positions are `Fin`.
- `stages` is `Always | between s t`, over `Stage = Higher | First |
  Graded | Owned | Lowered`. There are no other stages: "lifetimes
  decided" is `Graded`.
- A list of ops holds `SomeOp op`.
- `Meaning = CallsRuntime call | ComputedByRuntime call | Inline fn |
  HandFolder | NoFold`. A `ComputedByRuntime` op gets L13's
  `RuntimeFolds` trait and an `Abi<Op>` row.

**4. The effects seam (L01).** Core.Op imports
`IdrisMLIR.Spec.Effects.Declaration`, which exports:
- `Declaration : (i, o : Nat) -> Type`, an op's declaration, with
  positions into its operands and results;
- `ods : Declaration i o -> OdsEffects i o`, where Core.Ods holds MLIR's
  four kinds on a Resource (on the op, an operand or a result), typed
  rules by hand class name, and bodies.

That module imports only Core.Text, Core.Enums and Core.Ods, never
Core.Op or Vocabulary, which would be a cycle. The resource tree reaches
the C++ as `resources : List ResourceDef` in L01's Declarations.

**5. Each area exports `declarations : Declarations`** from
`IdrisMLIR.Spec.<Area>.Declarations`: ops, types, attributes, enums,
tables, interfaces, traits, directives, predicates, resources, helpers,
admitted, rewrites, skeleton, headers.
- `Spec.idr` imports exactly: Effects, Functions, Families, Grades,
  Lifetimes, Control, Runtime, Arrays, Ops.
- A per-area C++ header (`Grades.h.inc`, `Lifetimes.h.inc`,
  `Families.h.inc`, `NumericEnums.h.inc`) is a `Header` value (Core.Cpp:
  enums, tables, 1-D and 2-D arrays, scalars), printed to
  `foreign/idr/include/idr/IR/Generated/<name>.h.inc`.
- A closed set is `Closed a` (Core.Enums).

**6. Declarations with an owner fixed by the coordinator:**
- `idr.program` and its stage property: L02, in `Spec.Functions`.
- The crash causes' enum and the clock kinds: L11, in `Spec.Runtime`.
- Refusal rules: L03, in `IdrisMLIR.Spec.Core.Rules` (`Rule : Category
  -> Type`, `SomeRule`, phrase, scope). The frontend and the harness
  import it in place of `Spec.Rules`.

**7. Pass names** live in `Spec.Pipeline.Pipeline`. Each constructor is
`createIdr<Camel>()`, with its anchor and owner in parentheses:

| pass | anchor, stage change, owner |
| --- | --- |
| idr-defunctionalize | program, Higher to First |
| idr-knots | program |
| idr-in-place | program, L08 |
| idr-deduplicate | program, once, after knots |
| idr-contify | program, run twice |
| idr-optimize | program |
| idr-inline | program, L18: upstream's Inliner with idr-simplify |
| idr-columns | |
| idr-simplify | FuncOp, L14 |
| idr-structure-loops | FuncOp |
| idr-bufferize | |
| idr-accumulate | |
| idr-rc-cells | FuncOp |
| idr-lifetimes | program, First to Graded, L05; replaces idr-rc-stack |
| idr-rc-borrows | program; decides, writes signatures |
| idr-rc-place | FuncOp, L07 |
| idr-rc-exclusive | program, Graded to Owned, L08 |
| idr-rc-reuse | FuncOp, L07 |
| idr-rc-expand | FuncOp, L07 |
| idr-trmc | |
| idr-frames | |
| idr-tail-loops | FuncOp |
| idr-narrow | |
| idr-narrow-words | FuncOp, nested by idr-narrow |
| idr-lower-runtime, idr-lower-statics | program; C42's two passes |
| idr-lower | anchored on the program, Owned to Lowered; a pass cannot replace its anchor `idr.func`, so C42's per-function lowering runs inside it |
| idr-entry | module |
| idr-narrow-lanes | `llvm.func` |
| idr-tail-calls | module |
| idr-expect | module; a test check |
| idr-target | driver |

Gone: idr-effects, idr-demand, idr-rc-stack, idr-rc-grades,
idr-returned-arguments (and -drop), idr-binding-times, idr-identity, and
the idr-rc pipeline. Every stage change is a program or module pass
(`StagedPass`). Generated pass declarations stay
`idr/Transforms/Passes.h.inc`, from `IdrPasses.td`.
