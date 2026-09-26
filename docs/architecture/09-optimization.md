# 09. Optimization: what runs where

The optimizer is not one component. It is the assignment of each
optimization to the level where its facts exist (`GOAL-P1`):
1. **upstream MLIR**, when our dialect exposes the facts through traits,
   folders and interfaces;
2. **our C++ passes**, when the facts are in the dialect but upstream does not
   use them;
3. **the Idris middle end**, when the facts need dependent types, evaluation
   or TT.

Superoptimization, equality saturation and search are non-goals (D7).

## Safety

- **OPT-SAFE-1 (v0).** No optimization at any level may change behaviour
  under [03-semantics](03-semantics.md). In particular:
  - An operation that may crash is never removed, duplicated onto a path
    where it would not have run, or moved past another observable effect,
    unless it is proven not to crash. For `idr.div` and `idr.mod`,
    `IDR-EFF-1` encodes this so that upstream passes obey it.
  - A computation that may not terminate is never removed. `func.call` has
    no memory-effect interface, so upstream passes treat it as effectful and
    keep it. Removing calls to functions known to be total is a later
    optimization with its own rule.
  - No stage emits `mustprogress`, `willreturn` or equivalent assertions
    (`SEM-EVAL-5`).
  - Test: `tests/e2e/v0/crash-*.idr`, `tests/idr/effects/*.mlir`

## The ownership table

| Optimization | Source | Facts needed | Owner | Version |
| --- | --- | --- | --- | --- |
| Monomorphisation, instance specialization | Futhark `Monomorphise`, MLton, Lean `specialize` (`fixedInst`) | types, quantities, normalization | Idris middle end | v1 |
| Defunctionalisation, higher-order specialization | Futhark `Defunctionalise`, Lean `fixedHO`, MLton `ClosureConvert` | static function identity, profile restrictions | Idris middle end | v2 |
| Erasure of quantity 0 | Idris QTT, Lean `lcErased` | quantities | recorded in Idris; removed by our C++ `idr-lower` (1:0) | v0 |
| Forcing and detagging from indices | Brady, McBride, McKinna 2003 | index relationships in TT | Idris frontend | later |
| Proved rewrites | Lean `@[csimp]` | equality proofs in TT | Idris middle end | reserved ([07](07-proved-rewrites.md)) |
| Inlining | everyone | call graph, bodies | upstream `inline`, enabled by `IDR-IF-1` | v0 |
| Case-of-known-constructor, projection-of-constructor | Lean `simp`, GHC | constructor semantics | our folders (`idr.tag`, `idr.field`), run by upstream `canonicalize`; the known switch collapses by upstream `scf.index_switch` canonicalization | v0 |
| Constant folding and propagation | Lean `ElimDeadBranches` (constants) | constants | upstream `canonicalize` and `sccp`, through our folders | v0 |
| Constructor-set propagation (which constructors can reach a point) | Lean `ElimDeadBranches` abstract domain | constructor sets | our C++ analysis on MLIR's dataflow framework | later |
| CSE | Lean `cse`, Futhark CSE | purity | upstream `cse`, enabled by `Pure` traits | v0 |
| Dead code, dead functions, unused parameters | Lean `elimDead`, `reduceArity`; Futhark `removeDeadFunctions` | uses, purity | upstream `canonicalize`, `symbol-dce`, `remove-dead-values` | v0 |
| Sinking into branches | Lean `floatLetIn`, Futhark `Sink` | uses per region | upstream `control-flow-sink` | v1 |
| Unboxing and flattening of data | Futhark `ReplaceRecords`, MLton `Flatten`, Lean `structProjCases` | layout from dialect types | our C++ `idr-lower` (1:N type conversion); upstream `sroa` works only on memory | v0 |
| Enum as integer, single constructor without tag | upstream Idris (enum/newtype) | constructor shapes | our C++ `idr-lower` (`LOW-DATA-1`) | v0 |
| Self tail call to loop | MLton `Contify`, Lean join points | tail position (structural) | our C++ `idr-tail-loops`; upstream has no such pass | v0 |
| Other tail calls | | tail position, matching signatures | LLVM, best effort; guaranteed `musttail` later | later |
| Exact integer semantics (Euclidean division, zero guards) | Idris Chez backend | the semantics | our C++ `idr-lower` | v0 |
| Scalar peepholes, instruction selection, register allocation | | | LLVM `default<O2>` and codegen | v0 |
| Reference counting, reuse, borrowing, boxing | Lean impure phase, Perceus | ownership | excluded by the heap-free profile | after the memory design |
| Fusion | Futhark `fuseSOACs` | arrays | not in the profile | after arrays exist |

## Facts and their carriers

| Fact (from checked TT) | Carried as | Used by |
| --- | --- | --- |
| Quantity 0 | `!idr.erased` type, `idr.quantity = "0"` | `idr-lower` (1:0), CSE of `idr.erased` |
| Quantity 1 | `idr.quantity = "1"` | nothing in v0; kept for later memory work (never read as uniqueness, `GOAL-P5`) |
| Constructors, tags, fields | `idr.data` / `idr.ctor` | folders, `idr-lower` |
| Coverage | `IDR-MATCH-2` (last alternative as default) | the switch needs no default check |
| Impossible branches | dropped by the frontend (`FE-TR-4`) | smaller switches |
| Signedness | op choice (`IDR-IN-3`) | exact semantics |
| Source position | MLIR locations (`IDR-LOC-1`) | diagnostics, debug info |
| Totality | not carried in v0 | later: removing unused total calls, and `willreturn` once `SEM-EVAL-5` allows it |

## Pipelines

- **OPT-PIPE-1 (v0).** `idris-mlir-cc` runs exactly this pipeline. Steps 1–10
  are also available in `idris-mlir-opt` as `--idr-pipeline` (`DRV-OPT-1`).
  1. `idr-check-input`: the contract (`IDR-*`)
  2. `idr-tail-loops` (`LOW-TAIL-1`)
  3. `inline`, with the default simplification pipeline (`canonicalize`)
  4. `sccp`
  5. `canonicalize`
  6. `cse`
  7. `symbol-dce`
  8. `idr-lower` ([10-lowering](10-lowering.md))
  9. `canonicalize`, `cse`
  10. `convert-scf-to-cf`, `convert-to-llvm`, `reconcile-unrealized-casts`
  11. Translate to LLVM IR, run LLVM's `default<O2>` pipeline, then emit an
      object file for the host target (`LOW-TARGET-1`)
- **OPT-PIPE-2 (v0).** `idr-tail-loops` runs before `inline`, so that self tail
  calls are turned into loops before the inliner restructures recursive
  functions.
- **OPT-PIPE-3 (v0).** The inliner uses upstream's default policy. Code-size
  limits are a later tuning decision and need their own rule.
- **OPT-IDEM-1 (v0).** Running the pipeline's steps 3–7 a second time on
  their own output changes nothing. A difference means a missing
  canonicalization and is recorded as an issue, not a failure.
  - Test: `tests/idr/pipeline/fixpoint.mlir` (informative)
