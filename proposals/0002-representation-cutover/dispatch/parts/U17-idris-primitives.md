# U17 — One primitive set: generated IdrPrim, guards emitted by Emit

Mandatory findings: F-prim-1 F-guard-4

## Permitted outcome

1. **The generator.** `idris-mlir-tblgen -gen-idris-dialect` generates
   `IdrPrim`, `IdrRegionPrim`, `regionArity`, `primPerformsIO`,
   `primOp` and `regionOp` from the `Idr_Primitive` trait (C8.2). It
   fails on an `Idr_Primitive` op with an inherent attribute. Mandatory.
2. **`Types.idr`.**
   - `Prim` keeps only what `IdrPrim` does not cover, the constructors
     that are not one attribute-free op, and gains `Op IdrPrim`. An op
     that is an `IdrPrim` constructor is never also a `Prim`
     constructor: `NatToBig`, `NatFromBig` and `StrBuild` leave `Prim`
     for `Op NatToBig`, `Op NatFromBig`, `Op StrPack` and `Op StrConcat`,
     and `Builder` goes (C8.3);
   - the hand-written IO primitive type, its operand table and
     `ArrayLoop` are gone (C8.3).

   Mandatory.
3. **Emit.** `Emit/Operations.idr` has one generic case for `Op p`, and
   exports one function for an effect,
   `effect : Index -> Loc -> IdrPrim -> List Ty -> List Val -> DataId -> E (Maybe Val)`
   (C8.3), which U07's `EffectF` case calls. Both emit `guardOf`'s
   guard, with today's cause text, right before each partial primitive
   (C3.1, C3.2). Mandatory.
4. **The frontend.** `Frontend/Translate/Primitives.idr` builds `Op p`
   where it built a 1:1 pure `Prim`. Effects are built by U07's
   `Terms.idr` from U18's hooks. Mandatory.

## Owner / exclusive writes

- `CS/Types.idr`
- `CS/Emit/Operations.idr`
- `CS/Frontend/Translate/Primitives.idr`
- `foreign/idr/tools/idris-mlir-tblgen.cc`

**Excluded:**

- `CS/Dialect/Idr.idr`, which the coordinator regenerates with
  `tools/dialects.sh generate`.
- `CS/Registry` (U18 maps names to `Op p`).
- `CS/Term.idr` and `CS/Emit/Bodies.idr` (U07, which uses
  `IdrRegionPrim`).
- `INC/IdrOps.td`, where the coordinator places `Idr_Primitive`.

## Read first

- `contracts.md` C8 (all), C3.1, C3.2, C1.1 items 2, 3 and 7, and C13.
- `review.md` R10.
- `findings.md` F-prim-1 and F-guard-4.
- `foreign/idr/tools/idris-mlir-tblgen.cc`, all of it: how ops, builders
  and enums are generated today.
- `CS/Dialect/Idr.idr`'s generated op builders.
- `CS/Types.idr:240-509`.
- `CS/Emit/Operations.idr`, all of it.
- `CS/Frontend/Translate/Primitives.idr`.

## Fixed decisions

- **The constructor names** are the op's C++ class name without `Op`,
  in declaration order: `StrAppendOp` gives `StrAppend`, and
  `FileOpenOp` gives `FileOpen`.
- **`primPerformsIO p`** holds iff the op has `Idr_PerformsIO`. The
  world convention: an op with `Idr_PerformsIO` takes the world as its
  last operand, except `world.new`, which makes one and takes none. Every
  one gives the next world as its last result (`world.new` its only
  one). The hub's ops all follow it; `primOp` and `effect` rely on it.
- **`regionArity`** is the op's region's entry-block argument count, as
  its ODS states: 1 for `ArrayGenerate`, 3 for `ArrayFold`.
- **`guardOf : Prim -> List (Guard, Nat, String)`** lives in
  `Emit/Operations.idr`. It gives the guard kind, the index of the
  guarded operand, and the cause text, per C3.1's table. For `in_bounds`
  and `range`, Emit builds the length operand as `ArrayLength` builds it
  (`memref.dim`), or `idr.str.length` for `str.index`. Guards are built
  with the generated builders (`Idr.checkNonzeroOp` and the rest), and
  are never `IdrPrim`s.
- **The cause texts** are today's, copied exactly from the C++ crash
  causes C3.1 cites.
- **`Prim`'s constructors** (C8.3): `IntOp`, `IntShift`, `FloatOp`,
  `Negate`, `Math`, `Compare` and `Cast` (to `arith` and `math`),
  `ArrayLength` (`memref.dim` and an index cast), and the ops with an
  inherent attribute (C8.1). `str.pack`, `str.concat`, `nat.to_big` and
  `nat.from_big` are attribute-free and emitted one-to-one, so they are
  `IdrPrim`s. `StrBuild`'s `DataId` was its list operand's type, which a
  pure `Op p` takes from its operand.
- **An effect's type arguments** come from `Term.Effect`'s `List Ty`
  (U07, C8.3): `[e]` for an array primitive, `[t]` for `BufferLoad t`
  and `BufferStore t`, `[]` otherwise. `effect` reads them; nothing
  looks them up in a table in `Types.idr`. A pure `Op p`'s operand
  types are its operands' own types.
- **`effect`** does four things, in order: the guard (`guardOf`) for a
  partial primitive, the op by `primOp`, the world when
  `primPerformsIO p`, and the `IORes` instance named by the `DataId`.

## Inputs

- The `Idr_Primitive` trait and its placement (C1.1 item 7, C8.1).
- The guard ops (C1.1 item 2) and their generated builders.
- The C9 ops, which get constructors automatically.

## Outputs

- The generator's new output, and `Types.idr` and Emit on it.
- The mapping table (old `Prim`/`IOOp` constructor to `Op p`), for U18's
  registry.

## Implement

- **The generator.** Read records with `Idr_Primitive`. Split them by
  whether they have a region. Emit the data types, `regionArity`,
  `primPerformsIO`, `primOp` and `regionOp`, using the existing builder
  generation for operands and results. Error out on an inherent
  attribute.
- **`Types.idr`.** Replace each 1:1 constructor with `Op p`. Keep the
  rest. Remove the hand-written IO primitive type, its operand table and
  `ArrayLoop`, with their `Show` instances (see Delete).
- **`Emit/Operations.idr`.** Write the generic `Op p` case, and
  `effect` with the world threading and the `IORes` building that the IO
  cases do today. Add `guardOf` and the guard emission. Remove the
  per-constructor cases the generic ones cover. Keep the function
  Bodies calls for `PrimAppF`.
- **`Frontend/Translate/Primitives.idr`.** Adapt it to the new `Prim`.
- Write the mapping table into your handoff.

## Delete

- `IOOp`, `ioArgs`, `ArrayLoop`, and each 1:1 `Prim` constructor, with
  their `Show` cases. That includes `NatToBig`, `NatFromBig` and
  `StrBuild`, with their `primArgs` cases, `Builder` with its `Show`
  instance, and `ArrayOp` with its `Show` instance (the registry's
  `ArrayCall` carries the `IdrPrim`, C8.3).
- Each per-op emission case the generic `Op p` case replaces.

## NOT TO DO

- Do not regenerate `CS/Dialect/Idr.idr` by hand. The coordinator runs
  `tools/dialects.sh generate`.
- Do not change the registry (U18) or `Term.idr` (U07).
- Do not emit a guard for an op not in C3.1.
- Do not change a cause text.
- Do not change how `arith` and `math` primitives choose by signedness.

## Acceptance

- `tools/dialects.sh check` passes once the coordinator regenerates.
- `T/programs/` emit the same ops as at the launch base, plus guards
  before partial primitives. The coordinator compares the dumps' properties
  (U23's suites).
- `grep -rn 'IOOp\|ArrayLoop' compiler/src/IdrisMLIR --include=*.idr`
  finds nothing outside `Dialect/`.
- **Tempting partial:** generating `IdrPrim` but keeping `IOOp` "for the
  registry". Rejected: two homes for the primitive set.

## Escalate if

- A 1:1 primitive's op has an inherent attribute that C8.1 did not
  exclude. Report the op; the coordinator removes its trait.
- An IO primitive needs a type argument that is neither an array's
  element nor a buffer word's type. Report it, with where the frontend
  can read it.

## Stop and return

You are done when the generator, `Types.idr`, Emit and the frontend
are as above. Return the changed paths, the mapping table for U18,
`Verification: NotRun (swarm policy)`, and seams.
