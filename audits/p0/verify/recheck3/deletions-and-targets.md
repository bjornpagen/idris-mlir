<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 3: §6's deletions, §5's target shapes, PINS.md and upstream/

HEAD at start: f5736f12. HEAD at finish: bd4dd187. Lanes committed while
this was read. None of the files cited below changed in between: the
commits touched the fork's `Core/Name.idr`, `Primitives.idr` and
`TT/Var.idr`, the spec's `Effects/Resource.idr`, `Frontend/Growth/*`, and
P0, which gained D112, D113 and C225. Nothing was built or run. Searches
are `git grep --untracked` outside `audits/`, `proposals/`, `sources/`,
`third_party/` and `.claude/`. Owners come from `ownership.json`.

Grounds: *read* means the cited line was opened. *Measured* means a
grep/find count, or an "absent" search that returned nothing.

The rows recheck2 left open have been checked again against the live
tree. These are closed and not repeated: the 98 stale CMake sources (every
listed source exists and every source is listed, measured); the D50 `.txt`
rules; C43 and C201's stack sizes (`CMakeLists.txt:148-204`); C53's
precompiled header and `-fno-pch-timestamp` (`CMakeLists.txt:446`,
`foreign/idr/CMakeLists.txt:186`); `README.md`'s `!idr.lin`/`!idr.own`;
`tools/lanes/README.md`'s `DataRemap`; function numbering by name in
Contify, Demand and Deduplicate; the "1 MiB" comment in
`tests/tail-loop-deep`; `tests/llvm-bootstrap`, which now expects
assertions OFF.

The D68 growth proof (Proof/, Frontend/Growth*, Finite.idr, the run-time
re-check, C222, TS.readings) is in progress in L16. It is not detailed
here.

## INT

- **§5.2 library layering** `foreign/idr/lib/Support/CMakeLists.txt:8-22`,
  `foreign/idr/lib/Analysis/CMakeLists.txt:9-31`. §5.2 says "`IdrSupport`
  and `IdrSolve` naming no MLIR, D41's header under `runtime/` naming no
  LLVM or MLIR, `IdrIR` holding the one place an IR-handle map lives". In
  the tree, `IdrSupport` links `MLIRIR`, `MLIRPass` and `MLIRSupport`, and
  its headers include MLIR (`include/idr/Support/Actions.h:18-22`,
  `Profile.h:18`, `Remake.h:14-17`). `IdrSolver` links `IdrIR` and MLIR,
  and `ProgramGraph.cpp:9,60` reads `mlir::CallGraph`. D41's template
  names no MLIR (`Numeric/Inline.h`, `Small.h`, `Domain.h`), but it lives
  in `foreign/idr/include/idr/IR/Numeric/`, which the runtime includes
  (`runtime/Big/Arithmetic.cpp:7-8`). IR-handle numbering maps sit in at
  least eight units outside `IdrIR` (listed per lane below). P0 records no
  amendment (measured: `IdrSolve` appears once, at `:4745`). The code and
  the proposal disagree. INT, with L15 (Support) and L14 (Solver). (read)

## L03 (with L18)

- **generator gap: `ResultUsesMax`** `compiler/spec/IdrisMLIR/Spec/Generator/Ods.idr:300-301,867-869`
  prints `Idr_ResultUsesMax<...>`, a `ParamNativeOpTrait<"ResultUsesMax">`
  in `::idr`, and `Spec/Closures/Declarations.idr:229` puts it on every
  capture op. No C++ `idr::ResultUsesMax` trait exists. Absent:
  `grep -rn ResultUsesMax foreign/` finds only a comment at
  `lib/IR/OpsClosures.cpp:117`. The ODS the spec prints names a class that
  nothing defines. (measured)

## L04

- **stale comment** `foreign/idr/include/idr/IR/Symbols.h:34-39` says "An
  op's assembly format reads one as `custom<CtorRef>(ref(type($x)),
  $tag)`". No op's format has that directive (absent: `grep -rn CtorRef
  compiler/spec`). The only caller is the match cases' directive
  (`lib/IR/OpsMatchSyntax.cpp:57,73`). C19 deletes the `tag` attributes
  and their printers. (measured)
- **D112 (added during this read)** `foreign/idr/lib/IR/Layout/Layouts.cpp:382`:
  `llvm_unreachable("a comparison predicate")`. (read)

## L06

- **PINS entry naming a deleted file** `PINS.md:163`.
  `aarch64-sibcall-callee-pop`'s sites name
  `foreign/idr/lib/Conversion/TailCallPlan.cpp`, which is gone (absent:
  `ls foreign/idr/lib/Conversion`). (measured)
- **PINS sites naming Borrows on MLIR's solver** `PINS.md:142` and `:1031`
  (`dead-code-nested-symbol-use`, `dataflow-state-storage`) list "Ranges
  and Borrows". Borrows runs on no `DataFlowSolver`: the solver's users are
  `Analysis/Constants.cpp`, `Ranges.cpp`, `Narrow/Copy.cpp`,
  `Narrow/Lanes.cpp` and `Effects/Constants.cpp`. (measured)
- **PINS paths that no longer exist** `PINS.md:1084` names
  `foreign/idr/lib/IR/TypeGraph.cpp`, now
  `lib/Analysis/Solver/TypeGraph.cpp`. `PINS.md:275` names
  `harness/TwoLevels.idr`, which is gone. (measured)
- **PINS inline-unreachable stale** `PINS.md:487-489` says the body's end
  is what "the match canonicalization leave[s]". Our ops carry no
  canonicalization (D98; absent: `getCanonicalizationPatterns`). It also
  says idr-optimize calls `mlir::inlineCall` in
  `lib/Transforms/Optimize`, but the call is at
  `lib/Transforms/Inline/Inline.cpp:138`. The entry has no status line.
  (read)
- **PINS pass-timing names deleted passes** `PINS.md:711-712`: "idr-rc,
  idr-narrow, idr-returned-arguments". Neither `idr-rc` nor
  `idr-returned-arguments` is in the pass list (read:
  `Spec/Pipeline/Pipeline.idr:196-532`). (read)
- **carried patch READMEs naming deleted passes or paths**
  `upstream/19-pass-timing-dynamic-pipeline/README.md:14-15` names
  `idr-eval` and `idr-canonicalize` as reaching the bug.
  `upstream/04-vectorize-precondition-body/README.md:97-99` names
  `idr-vectorize` in `foreign/idr/lib/Vectorize/Tiles.cppm`; the site is
  `lib/Target/Schedules.cpp:182`. `upstream/81-attr-type-walker-iterative/README.md`
  names `lib/IR/TypeGraph.cpp`. (measured)
- **fixture marks no file has** `tools/licenses.sh:49` lists `*/live-cells`
  and `*/default-stack`. No file in `tests`, `bench` or `harness` has
  either name, and nothing reads them. The live-cell counter is gone.
  (measured)

Checked and fine: every carried `.patch` has its `tests/upstream-<bug>`
check and a PINS entry. Each retired patch (01, 02, 06, 08, 16, 17, 22, 23,
25, 28, 48, 58, 63, 78, 96) has only `pull-request.diff` and is recorded as
a submission in `PINS.md:21-110` or `upstream/README.md`. Patches 05, 07,
19, 29, 56 (through `DependsOnParent`, `EGraph/Build.cpp:51`), 72, 73 and
77 are still reached.

## L07

- **D112** `foreign/idr/include/idr/Transforms/Counting/Facts.h:61`:
  `llvm_unreachable("who frees a value is one of three")`. (read)

## L08

- **IR-handle numbering maps (§5.2)** `lib/Transforms/InPlace/Unique.cpp:218`
  and `UniqueResults.cpp:207`: `llvm::DenseMap<Value, Local> number`.
  (read)

## L09

- **IR-handle numbering map (§5.2)** `lib/Transforms/Joins/IdenticalRegions.cpp:43`:
  `llvm::DenseMap<Value, unsigned> number`. (read)

## L11

- **D112** `foreign/idr/lib/Driver/Main.cpp:56`, `Options.cpp:331`,
  `Outcome.cpp:62`: `llvm_unreachable` after exhaustive switches. (read)

## L12

- **the element take's test (§6, C39)** `foreign/idr/lib/Conversion/Elements.cpp:109-135`.
  `boxSharingOf` decides by grade in the lowering. `takeOut` still
  branches on `runtime.isUnique` for a boxed element (`:125`), and in the
  shared path it writes `inc`, `dec` and a fresh allocation. On one side,
  C39 deletes `Elements.cpp:64-82` (`takeElement`'s run-time test) and
  §5.5 says "the lowering decides nothing". On the other, the code's
  comment says sharing "is known only here, at run time". (read)
- **IR-handle numbering maps (§5.2)** `include/idr/Transforms/Narrow.h:305`
  (`DenseMap<Operation *, uint32_t>`) and `BufferizeModels.h:79`
  (`DenseMap<Value, uint32_t>`). (read)

## L14

- **cycle decider restated** `lib/Analysis/Ranges.cpp:189-192` and
  `include/idr/Analysis/Solver/SummarizeImpl.h:42` each decide that a
  component is cyclic with `members.size() > 1 || callsItself(...)`. That
  is the rule `ProgramGraph::onCycle` holds (`ProgramGraph.h:140-141`).
  §6 deletes "the four cycle deciders". (read)
- **pointer-keyed map (§5.2)** `lib/Transforms/EGraph/Simplify.cpp:95`:
  `footprint::DenseMap<Operation *, Root> roots`. (read)

## L16

- **T2's readers (L16 §2.6, which §6 points to)**
  `compiler/src/IdrisMLIR/Frontend/Translate/Cases.idr:307-325`
  (`siblings`, the constructors found through the first constructor's
  type), `:331-335` (`coversAll`'s re-derivation) and `:400` (`instanceOf`)
  remain. The TTC keeps `scTy` (`compiler/idris/src/Core/TTC.idr:868,932`)
  and `Cases.tree` reads it (`Cases.idr:508`). (read)
- **main source path recovered** `Frontend/Resolve.idr:93-104`.
  `elaboratedFile` rebuilds the main file's path from its checked module's
  path. L16 §1.3 and L17 §2.2 make it the driver's. (read)
- **names as strings in the registry** `Registry/Libraries.idr:123-128,137,143-144`.
  `admittedFromPrimIO : SortedSet String` and
  `elem q.name ["assert_total", "assert_smaller"]` are tested against
  each `QName` at every `admits` and `assertion` query. (read)
- **hand files that claim to be generated** `compiler/src/IdrisMLIR/Dialect/Idr.idr:3-5`
  and `Encoding/Wire.idr:1-3` carry "Generated by specgen ... Do not
  edit". They were written by hand (a7bc3107, 257e80c0, 0222f1dc), outside
  `Generated/`, and no manifest covers them. (read)
- **D68 growth proof**: in progress.

## L17

- **dead namespace** `compiler/idris/src/Core/Name/Namespace.idr:242-243`
  (`partialEvalNS`) and `Core/Context.idr:66` (`visibleNS =
  [partialEvalNS]`). `TTImp/PartialEval.idr` is deleted, and nothing
  defines a name in `_PE` (measured: the only hits are those two lines and
  `K_PE` in the vocabulary). (measured)

## L18

- **function map by name** `include/idr/Transforms/SpecializeState.h:212`:
  `llvm::DenseMap<mlir::StringAttr, Node *> byName`, beside
  `byFunction` by `FunctionId` (`:217`). §6 deletes "every function
  membership, number or callers map by name or by pointer". The comment
  (`:209-211`) gives as its reason that a second key on one name is an
  error. (read)

## L19

- **an effect reading outside the one API** `foreign/idr/lib/Transforms/Expect/ResetsUnshared.cpp:29-40`.
  `onCountOf` takes `MemoryEffectOpInterface` instances itself, where the
  API's `effects::eachOwnEffect` does that
  (`include/idr/IR/Effects/Classify.h:75-87`). It is the only reader of
  MLIR's instances outside `IR/Effects*` (measured). (read)
- **caller-only symbol map, and a comment that no longer holds**
  `lib/Transforms/Expect/Continuations.cpp:17-28`. It builds a
  `SymbolUserMap`, the last of L14 §1.4's seven (measured), and says the
  users are counted "as idr-contify counts them, by upstream's map of
  symbol users". Contify now reads the program graph
  (`Optimize/Contify.cpp:130-140`). (read)
- **function map by name** `include/idr/Transforms/Contracts.h:55`:
  `DenseMap<StringAttr, unsigned> bySymbol`. L14 §1.4 moves Contracts to
  the graph builder. (read)
- **function numbering by pointer** `include/idr/Transforms/Expect.h:214-223`.
  `FunctionNumbering` keeps `DenseMap<Operation *, uint32_t>` over the
  program's functions, beside the program graph's `FunctionId`. (read)

## L21

- **take_into's lowering decides and counts** `foreign/idr/lib/Conversion/Lower/Counting.cpp:107-155`.
  `LowerTakeInto` folds by grade at the lowering
  (`claims(..., Unique::Self)`, `:126`). Otherwise it branches on
  `runtime.isUnique` and writes `inc`, `dec` and `allocate` for the
  shared path (`:132-148`). On one side, C39 introduces `idr.take_into` as
  the fused take. On the other, it says "Moves and counts are IR; the
  lowering lowers primitive ops only" and deletes "the lowering's
  uniqueness branches", and §5.5 says the lowering decides nothing.
  (read)

## Checked and done

§6, item by item: 131 items checked (P0's list plus the symbols in the
lanes' deletion lists it points to: L02 §1.4, L05 §2.10, L07 §2.15, L09
§2.11, L14 §1.4/§2.10, L16 §2.6, L17 §2.8). 116 have no reference left.
Among them: every effect symbol of §5.1's "Deleted" list; the
`#idr.types`/`MutableType`/`DataRemap`/`DataBody`/`Fit`/`!idr.box`/kind
and role names; every old grade, lifetime, view and frame spelling;
`ValueFacts`' hand answers; the 38 hand folders (21 folds left, none a
runtime call); `CallCycles`, `Recursion`, `Scc`, `MonotoneWorklist`,
`FiniteLattice`, `lib/Analysis/Effects.cpp`, Returned; `Reuses`, `Uses`,
`Classes`, `Take`, Reshape's predictors, `Owned*`, `madeStatic`,
`isStatic`, `idr-rc-stack`, the stack bit; `Tail/Loop`, `WhileDo`,
`Frame.cpp`, `TailCallPlan`, `TailPosition`, the enclosing-match walks,
the poison yields; the `Fields` table, `heapRegion`, the 4 GiB
reservation, the `Status` root, the `idris-mlir:` prefix, the live-cell
counter; the greedy driver, `canonicalize`, CSE, `Canon/`; the `Nat`
chain (`Terms.idr:1648-1663`) and `WithBounds` (`Bounded.idr:76-78`);
`Nests`, `GeneratingOpInterface` and the rest of the arrays list;
`Forced.idr`, the five erasure readers, `idr.refusals`, `Newtype`,
`terminating`, `delayedLets`, decimal doubles; every L17 §2.8 symbol; the
`remove-dead-values` registration; patches 06, 28, 63 retired; the
bench's `ulimit -s`; `defunc-tag-limit`; the toolchain's assertions;
every `assert(`.

§5, by area: the effect tree's twelve resources, rows on ops, the effect
LLVM mapping and `tests/runtime-effects`; no `TypeSwitch`, no
`std::function`, no hand `.td`; every lifetime opener, `activation`,
`lend`, `token.rebuild`, `io.clock`, `crash.cause`/`crash.message`,
`io.exit`, joins, loops and jumps; `match_unique`, the cells, tokens and
destinations; the six index-term forms; the counting passes in §5.5's
order; the stack layout; the `TailKind` checks. Of the target shapes
checked, all but the layering finding (INT) are present.
