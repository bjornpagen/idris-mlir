# 09. Optimization: what runs where

The optimizer is not one component. It is the assignment of each
optimization to the level where its facts exist (`GOAL-P1`):
1. **upstream MLIR**, when our dialect exposes the facts through traits,
   folders and interfaces;
2. **our C++ passes**, when the facts are in the dialect but upstream does not
   use them;
3. **Idris**, when the facts need dependent types, normalization or TT.

*Revised at the cutover:* every fact a program optimization needs is in the
dialect: constructors, closures, strings, bigs, totality, effects. So
every optimization of the program is MLIR's, and Idris keeps only
monomorphisation and the representations, which need types. Before, the
Idris middle end removed abstraction first (`Simplify`), and MLIR
optimized first-order code.

Superoptimization, equality saturation and search are non-goals (D7).

## Safety

- **OPT-SAFE-1 (v0).** No optimization at any level may change behaviour
  under [03-semantics](03-semantics.md). In particular:
  - An operation that may crash is never removed, duplicated onto a path
    where it would not have run, or moved past another observable effect,
    unless it is proven not to crash. The dialect's traits encode this, so
    that upstream passes obey it: `IDR-EFF-1`, where a crash also writes
    the IO resource, so that no pass orders it differently with output.
  - A computation that may not terminate is never removed. `func.call` has
    no memory-effect interface, so upstream passes treat it as effectful and
    keep it; the dialect removes an unused call only under `OPT-CALL-1`. A
    loop in a function that is not total carries `idr.may_loop`
    (`LOW-TAIL-4`).
  - An evaluation at compile time that crashes leaves its call in place
    (`ELIM-EVAL-1`).
  - No stage emits `mustprogress`, `willreturn` or equivalent assertions
    (`SEM-EVAL-5`).
  - Test: `tests/e2e/v0/crash-*`, `tests/idr/effects/*.mlir`,
    `tests/idr/canon/case-of-case.mlir`
- **OPT-CALL-1 (v3).** An unused `func.call` is removed exactly when its
  callee is pure, total and cannot crash (`idr.effect = "pure"`,
  `idr.total`, no `idr.may_crash`: `IDR-FACT-1`), and every argument that
  may hold a closure is a constant whose closures name only functions
  that satisfy the same condition. Totality alone does not suffice: a crash
  happens even when its result is unused (`SEM-EVAL-4`). It is a
  canonicalization that the dialect adds for `func.call`, so every
  `canonicalize` applies it.
  - Check: the dialect's canonicalization of `func.call`
  - Test: `tests/idr/canon/unused-call.mlir`

## The ownership table

| Optimization | Source | Facts needed | Owner | Version |
| --- | --- | --- | --- | --- |
| Monomorphisation, instance specialization | Futhark `Monomorphise`, MLton, Lean `specialize` (`fixedInst`) | types, quantities, normalization | Idris (`ELIM-MONO-*`) | v1 |
| Representations: unboxed sum, box, big | MLton, Lean's scalar `Nat`, Idris's `ZERO`/`SUCC` flags | types, recursion, constructor flags | Idris (`Frontend.Translate`, `IDR-DATA-4`, `IDR-IN-3`) | cutover |
| Loop breakers | GHC's inliner | the call graph of full Core, the registry's *Break last* | Idris (`Emit`, `OPT-PIPE-3`) | v2 |
| Inlining | everyone | call graph, bodies | upstream `inline`, enabled by `IDR-IF-1`, with no size threshold (`OPT-PIPE-5`) | v0 |
| Beta, force of delay | GHC, Lean `simp` | known closures | our canonicalization of `idr.apply`, then `inline` (`ELIM-G-1`, `ELIM-G-8`) | cutover |
| Case-of-known-constructor, projection-of-constructor | Lean `simp`, GHC | constructor semantics | our folders (`idr.tag`, `idr.field`) and region patterns (`idr.match`), run by upstream `canonicalize` (`ELIM-G-2`) | v0 |
| Case-of-case | GHC, Lean | a match's single consumer | our canonicalization of `idr.match` (`IDR-MATCH-5`) | cutover |
| Specialization on static arguments, higher-order specialization | Futhark `Defunctionalise`, Lean `fixedHO`, call-pattern specialization | constant-like arguments | our C++ `idr-specialize` (`ELIM-SPEC-1`) | cutover |
| Compile-time evaluation | MLton constant folding, Zig `comptime` | closed total pure calls | our C++ `idr-eval`, which runs the program's own code (`ELIM-EVAL-1`) | cutover |
| Constant folding and propagation | Lean `ElimDeadBranches` (constants) | constants | upstream `canonicalize` and `sccp`, through our folders (`ELIM-G-6`) | v0 |
| Defunctionalization of closures that remain | Reynolds, MLton `ClosureConvert` | sets of functions | our C++ `idr-defunctionalize` on MLIR's dataflow framework (`ELIM-CLOS-1`) | cutover |
| Monad elimination (IO, State, Reader, …) | GHC's state hack, Lean's IO representation | known binds and continuations | the passes above together: inlining, beta, known constructor, specialization | v1 |
| Output fusion (`putStr (a ++ b)` becomes two writes) | | `SEM-IO-2` | our DRR canonicalizations of `idr.io.put_str` (`ELIM-G-7`) | v1 |
| What is known about runtime strings | | the pieces of a string | our canonicalizations (`ELIM-G-15`) | v3 |
| IO effect ordering | | world chain | `!idr.world` values plus `IDR-EFF-2`, so upstream passes keep the order | v1 |
| Erasure of quantity 0 | Idris QTT, Lean `lcErased` | quantities | recorded in Idris; removed by our C++ `idr-lower` (1:0) | v0 |
| Forcing and detagging from indices | Brady, McBride, McKinna 2003 | index relationships in TT | Idris frontend | later |
| Proved rewrites | Lean `@[csimp]` | equality proofs in TT | Idris | reserved ([07](07-proved-rewrites.md)) |
| Integer ranges | | tags, characters, lengths | upstream `int-range-optimizations`, through `IDR-RANGE-1` | cutover |
| CSE | Lean `cse`, Futhark CSE | purity | upstream `cse`, enabled by `Pure` traits | v0 |
| Dead code, dead functions, unused parameters | Lean `elimDead`, `reduceArity`; Futhark `removeDeadFunctions` | uses, purity | upstream `canonicalize`, `symbol-dce`, `remove-dead-values`; unused calls by `OPT-CALL-1` | v0 |
| Self tail call to loop | MLton `Contify`, Lean join points | tail position | our C++ `idr-tail-loops` (`LOW-TAIL-5`) | cutover |
| The heap-free profile | | what allocates | our C++ `idr-check-profile` (`PROF-HEAP-*`) | cutover |
| Unboxing and flattening of data | Futhark `ReplaceRecords`, MLton `Flatten`, Lean `structProjCases` | layout from dialect types | our C++ `idr-lower` (1:N type conversion); upstream `sroa` works only on memory | v0 |
| Enum as integer, single constructor without tag | upstream Idris (enum/newtype) | constructor shapes | our C++ `idr-lower` (`LOW-DATA-1`) | v0 |
| Other tail calls | | tail position, matching signatures | LLVM, best effort; guaranteed `musttail` later | later |
| Exact integer semantics (Euclidean division, zero guards) | Idris Chez backend | the semantics | our C++ `idr-lower` | v0 |
| Merging identical functions | | identical code | LLVM `MergeFunctions` | cutover |
| Scalar peepholes, instruction selection, register allocation | | | LLVM `default<O3>` and codegen | v0 |
| Constructor-set propagation (which constructors can reach a point) | Lean `ElimDeadBranches` abstract domain | constructor sets | our C++ analysis on MLIR's dataflow framework | later |
| Reference counting, reuse, borrowing | Lean impure phase, Perceus | ownership | excluded by the heap-free profile | after the memory design |
| Fusion | Futhark `fuseSOACs` | arrays | not in the profile | after arrays exist |

## Facts and their carriers

| Fact (from checked TT) | Carried as | Used by |
| --- | --- | --- |
| Quantity 0 | `!idr.erased` type, `idr.quantity = "0"` | `idr-lower` (1:0) |
| Quantity 1 | `idr.quantity = "1"` | nothing yet; kept for later memory work (never read as uniqueness, `GOAL-P5`) |
| Constructors, tags, fields | `idr.data` / `idr.ctor` | folders, matches, `idr-lower` |
| Recursion | `idr.data … box` (`IDR-DATA-4`) | `idr-lower`, `idr-check-profile` |
| Coverage | alternatives left out of `idr.match` (`IDR-MATCH-2`) | smaller switches |
| Totality | `idr.total` (`IDR-FACT-1`) | `idr-eval`, `OPT-CALL-1`, `idr.may_loop` |
| Effects, crashes | `idr.effect`, `idr.may_crash`, computed by `idr-effects` | `idr-eval`, `OPT-CALL-1` |
| World linearity | `!idr.world` values, `IDR-WORLD-1` | effect order, and 1:0 lowering |
| Constants | `idr.constant`, `arith.constant` (`IDR-CONST-*`) | folders, specialization keys, static data |
| Signedness | op choice (`IDR-IN-3`) | exact semantics |
| Source position, library origin | MLIR locations (`IDR-LOC-1`) | diagnostics, debug info |

## Pipelines

- **OPT-PIPE-1 (v0).** `idris-mlir-cc` runs exactly this pipeline. Steps 1
  to 10 are also available in `idris-mlir-opt` as `--idr-pipeline`
  (`DRV-OPT-1`).
  1. `idr-simplify`, the simplify loop (`OPT-PIPE-5`)
  2. `idr-defunctionalize` (`ELIM-CLOS-1`)
  3. `canonicalize`
  4. `idr-tail-loops` (`LOW-TAIL-5`)
  5. `idr-check-profile` (`PROF-HEAP-*`)
  6. `idr-lower` ([10-lowering](10-lowering.md))
  7. `canonicalize`
  8. `cse`
  9. `convert-scf-to-cf`
  10. `convert-to-llvm`, `reconcile-unrealized-casts`
  11. Translate to LLVM IR; join the bitcode of the runtime archive, only
      what the program reaches (`TC-LINK-1`); internalize every symbol but
      `main`; run LLVM's `default<O3>` pipeline without FP contraction and
      with `MergeFunctions`; then emit one object file for the target CPU
      (`LOW-TARGET-1`), laid out as `OPT-PIPE-4` says

  The module is verified after every pass (`DIAG-ICE-1`). *Revised at the
  cutover:* before, the pipeline was `idr-check-input`, `idr-entry`,
  `inline`, `sccp`, `canonicalize`, `cse`, `symbol-dce`, then `idr-lower`,
  on first-order code.
  - Test: `tests/idr/pipeline/cc-steps.mlir`
  - *Measured and left out:* upstream `control-flow-sink` changed no
    benchmark in `bench/` beyond noise (v2); LLVM's own sinking already
    moves those operations.
- **OPT-PIPE-2 (v0 only; withdrawn in v3).** loops are made in first-order Core
  (`CORE-LOOP-1`), before MLIR; a self tail call that exists only after
  MLIR inlines is left to LLVM (`LOW-TAIL-3`). *Since the cutover*, loops
  are made in MLIR again, by `idr-tail-loops` after the simplify loop.
- **OPT-PIPE-3 (v2).** The inliner inlines on a call graph whose cycles are
  already cut. `Emit` marks *loop breakers* `no_inline`, as GHC does
  (Peyton Jones and Marlow, "Secrets of the Glasgow Haskell Compiler
  inliner", JFP 2002): in every strongly connected component of two or more
  functions of full Core's call graph it picks one, the first in program
  order that is not from a library module whose functions break last
  (`Builtin` or `PrimIO`: the *Break last* column of the library table,
  [17-registry](17-registry.md)), and repeats on the rest of the
  component. Everything else may be inlined, which cannot unroll a loop,
  and each breaker becomes self recursive. A clone of a loop breaker
  inherits `no_inline` (`ELIM-SPEC-1`). Without it the inliner unrolled
  mutual recursion between an IO loop and its `>>` specialization until a
  200-function program took over a minute and grew twentyfold. *Revised at
  the cutover:* the breakers are computed by `Emit`, on full Core; before,
  on first-order Core.
  - Check: `Emit`
  - Test: `tests/e2e/v2/loop-breakers/mlir.check`
- **OPT-PIPE-4 (v3).** Code generation aligns every function, and every
  block that is not reached by falling through, to 64 bytes
  (`--align-all-functions=6 --align-all-nofallthru-blocks=6`, which the
  command line can override). The padding is never executed. Without it a
  hot loop's speed depended on where unrelated code put it: `tak` ran 10%
  slower when only the code that reads its input changed, with identical
  machine code for `tak` at a different address. With it, no benchmark in
  `bench/` is slower and `fib` is 9% faster.
  - Test: `tests/idr/pipeline/layout.mlir`
- **OPT-PIPE-5 (v3). The simplify loop.** `idr-simplify` repeats this
  round until a round leaves the module unchanged, as its
  `OperationFingerPrint` shows:
  1. `idr-effects` (`IDR-FACT-1`)
  2. `inline`, with `default-pipeline=canonicalize`, `max-iterations=K`
     and no inlining threshold
  3. `idr-specialize`: each call is first raised (`ELIM-G-5`), then
     specialized (`ELIM-SPEC-1`)
  4. `sccp`, `canonicalize`, `cse`
  5. `idr-eval` (`ELIM-EVAL-1`)
  6. `idr-prune`, `remove-dead-values`, `symbol-dce`

  The inliner's values:
  - **No threshold** (`inlining-threshold` unlimited, upstream's default):
    every legal call is inlined. With a finite threshold, whether a string
    reached output fusion, and so whether a program compiled, would depend
    on a cost model (`PROF-GEN-5`).
  - **`K`** is 4 (upstream's default; tuned on `bench/` at stop point 3).
    It bounds how often the inliner re-simplifies an SCC in one round; the
    loop repeats the round anyway, so `K` changes compile time, never
    whether a program compiles.
  - `idr-prune` runs right before `remove-dead-values`, which at the pin
    crashes on code that dead-code analysis proves unreachable but nothing
    has removed yet. With the same analyses, it ends each such match region
    in `ub.unreachable` and makes each such function return `ub.poison`
    (`PINS.md`: `prune-before-remove-dead-values`). It also makes a call
    of a function that a closure names pass `ub.poison` for each parameter
    the function never reads, which `remove-dead-values` would otherwise
    leave a null operand (`PINS.md`: `remove-dead-values-address-taken`).
  - Raising is a step of `idr-specialize`, right after `inline`: inlining
    the IO monad's bind is what puts the call that builds an action next
    to the apply that runs it (and output fusion, in the canonicalizations
    the inliner runs, puts a call that builds a string next to its
    output), and a raised call, which now takes the world or the apply's
    arguments, is specialized in the same run. It shares the clone limit,
    the clones' keys and their facts with specialization. Each new clone
    is canonicalized when it is made, so the next round inlines calls, not
    applies of closures.

  *Why the loop terminates.* Inlining never goes around a cycle, because
  loop breakers cut every cycle of the call graph (`OPT-PIPE-3`), and
  clones inherit `no_inline`. Specialization is bounded by the clone limit
  and by the growth stop (`ELIM-SPEC-2`). Raising makes clones under the
  same limit, and a raise that makes none removes an apply
  (`ELIM-G-5`). Every evaluation terminates (`SEM-EVAL-6`) and replaces a
  call by constants, and there are finitely many calls to evaluate once
  inlining and specialization are bounded. The other passes only shrink the
  module. So after finitely many rounds nothing changes.
  - Check: the pass `idr-simplify`
- **OPT-IDEM-1 (v0).** *Revised at the cutover:* the simplify loop runs to a
  fixpoint, so running it again on its own output changes nothing. A
  difference in the rest of the pipeline means a missing canonicalization
  and is recorded as an issue, not a failure.
  - Test: `tests/idr/pipeline/fixpoint.mlir` (informative)

## Upstream limitations at the pin

LLVM and MLIR are pinned at `llvmorg-23.1.2`. These limitations shape the
pipeline; each workaround has a `PINS.md` entry:

| Limitation | Where | What we do |
| --- | --- | --- |
| The inliner's default `handleTerminator` cannot inline a callee whose body ends in `ub.unreachable`, and the `ub` dialect does not implement it | `DialectInlinerInterface.td` | no function body ends in `ub.unreachable`: one that never returns returns `ub.poison` (`IDR-CRASH-1`; `inline-unreachable`) |
| `remove-dead-values` erases the arguments of a function that dead-code analysis never reaches but keeps the ops that use them, then crashes | `RemoveDeadValues.cpp:649`, `:833` | `idr-prune` empties unreachable code first (`prune-before-remove-dead-values`) |
| upstream region inlining (`populateRegionBranchOpInterfaceInliningPattern`) skips a region that ends in `ub.unreachable` | the region patterns | none: a match whose taken region crashes stays a match, and `idr-lower` lowers it |
| `mlir::ExecutionEngine` aborts in a static-musl process, creating its process-symbol generator | `ExecutionEngine.cpp:393-395` | `idr-eval` uses ORC's `LLJIT` directly, with an absolute-symbol table (`orc-lljit`) |
