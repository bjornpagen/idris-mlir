<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 3: the C++ rule sweep of foreign/idr and runtime/

HEAD `bd4dd187` at start and at finish. The working tree was read; it has no
uncommitted change under `foreign/` or `runtime/`. The sweep covers 589 files:
every `.cpp`, `.h`, `.inc`, `.td` and `.c` under `foreign/idr` and `runtime/`,
with `include/idr/IR/Generated/` left out. Nothing was built, typechecked or
run.

Grounds: *measured* means a grep, `git grep`, `find` or `wc` over the tree, or
a scan that strips comments and strings (`match(` arguments, self-calls,
clusters of `dyn_cast`/`isa` over op classes). *Read* means the cited lines
were opened. Each finding's owner is the longest prefix in `ownership.json`.

The rules swept: AGENTS.md's C++ and analysis rules; C52 (one fold, no
accessors); C200 (no catch-all case in a `match`); C184 (no header under
`lib/`); D91 (no assert); C99 (no recursion on input size); and the 400-line
limit.

## L02

- **Dead licence query** `include/idr/Analysis/Effects.h:65` — `licensesDropOrMove` has no caller anywhere (`git grep -w` finds only its definition). AGENTS.md makes this row question the one licence to delete or move a call, but no pass asks it. Delete it, or route every delete and move through it (measured).

## L03

- **Dead helpers in the TableGen backend** `tools/idris-mlir-tblgen.cpp:246-287` — `traitsOfClass`, `markOf`, `operandNamed` and `resultNamed` are unreferenced. `traitsOfClass`'s only caller is `markOf`, which nothing calls (measured: one hit each, two for `traitsOfClass`).
- **Upstream records read by their C++ spelling** `tools/idris-mlir-tblgen.cpp:567-591, 822, 914-939` — attributes are classified by comparing storage-type text (`storage == "::mlir::IntegerAttr"`, `"::mlir::UnitAttr"`). Parameters are classified by comparing C++ type text (`cpp == "unsigned"`, `cpp.starts_with("::") && cpp.ends_with("Type")`). AGENTS.md lists "the TableGen backend reading records by C++ spelling and name strings (14 T06, T34)" as a "never". D51 keeps the backend but says it reads upstream's records through MLIR's TableGen API. The code does use `mlir::tblgen` there, but it decides by string compares, not by record class membership (read).

## L04

- **Op ladder** `lib/IR/Symbols.cpp:75-82` — the `eliminates` lambda chains `dyn_cast_or_null` over `DataMatchOp`, `DataFieldOp` and `IoPutStrOp`, each case reading a different operand: dispatch over our ops by hand (read).
- **Recursion on a type's nesting** `include/idr/IR/Families/Families.h:190-213` — `builds` calls itself for each field pair of an `in_place` target, so its depth is how deeply the program nests in-place types. C99 says "a type's recursive facts are bits computed when it is made" (read).
- **A second fold beside `match`** `lib/IR/Layout/Components.cpp:88-106` — `foldDialect` runs `isa<Ts>` over every type of the dialect, one compare per class, and returns `*std::move(out)` from an `optional`. C52 allows one exhaustive fold. Shared shape over the dialect's types is an MLIR interface, not an isa chain (read).
- **Run-time re-test of what the type states** `lib/IR/Layout/Layouts.cpp:186-201` — `Layouts::sum` and `Layouts::cells` call `reportFatalInternalError` when a caller asks an in-place type for its cells, or a cell type for its slots. The `DataType`'s layout class already fixes which call is legal. The code's comment calls this "Essential"; D91 says such an invariant becomes "a type, a verifier rule, or nothing". Both sides are recorded here (read).
- **Re-test of a verifier rule** `lib/IR/Layout/Components.cpp:174-179` — a fatal internal error when a memref has no strides. The comment itself says "the program's verifier refuses" such a memref. D91 calls for nothing here (read).

## L05

- **Dead function** `include/idr/IR/Ownership.h:59`, `lib/IR/Verify/Uses.cpp:206-215` — `idr::ownership::readThrough` is declared and defined but never called (measured: two hits, the declaration and the definition).
- **Dead accessor** `include/idr/IR/Lifetimes.h:109` — `LifetimeKind::isHome` has no caller (measured: one hit).

## L07

- **One fact held twice** `include/idr/Transforms/Counting/Facts.h:45-62` — `enum class Counts { None, Counted, Scoped, Static }` restates `Release` (`Counted`, `Scoped`, `Static`) with "no hold" added. `countsOf` maps one enum to the other by a `switch` ending in `llvm_unreachable`, and 17 references use the copy. An `optional<Release>` from the grade would carry the same fact (read; measured count).

## L09

- **Static work built per function** `lib/Conversion/Matches.cpp:386-396` — `lowerControlFlow` builds a `RewritePatternSet` (SCF-to-CF plus the join lowering) and a `ConversionTarget` on every call. idr-lower calls it once per function, from parallel workers (`lib/Conversion/Lower.cpp:226, 272`), while every other part of `Lowering` is built once (`Lower.cpp:99-102, 160-201`). This is the "built per function what is the same for every function" shape that AGENTS.md lists as a "never" (51a4771b) (read).

## L11

- **Hand vtable over a closed sum** `runtime/Io/Io.h:150-198` — `StreamOps` holds nine function pointers, with one row for each of four stream kinds (`inputStream`, `outputStream`, `errorStream`, `fileStream`, `:178-181`). That is type erasure over a closed set of ours, where AGENTS.md asks for one fold over a closed sum. No upstream or OS API requires this table (read).
- **The C ABI recognised by name prefix** `lib/Driver/Prepare.cpp:73-75` — the runtime module is internalised by `value.getName().starts_with("idris_rt_")`. Which functions form the ABI is a static fact the generated runtime table already holds, so this is a string compare of a static fact (read).
- **A pattern per registered op, chosen by name** `tools/idris-mlir-reduce.cpp:58-63` — `populateReductionPatterns` adds one `PoisonResults` for every registered op and skips `ub.poison` by comparing its name string. AGENTS.md's "never" for 7987388b names this shape: patterns rooted at every registered op, minus a hand list (read).

## L12

- **Op ladder left after the interface (D7, partial)** `lib/Transforms/Narrow/Narrow.cpp:139-151` — the head is now `BigOfIntegerOpInterface`, but separate `isa<BigToIntOp>`, `isa<ub::PoisonOp>` and `isa<ConstantOp>` cases follow it. The comment two lines above says "never a list of ops" (read). The StructureLoops half of D7 is done: `Forms.cpp:83-97` reads the commutativity trait and `laws::identityOf`.
- **A bool choosing a case, plus a sentinel** `include/idr/Transforms/Narrow.h:284-288` — in `LaneWidth{unsigned bits; bool lanes;}`, `lanes` picks scalar or vector, and `{0, false}` stands for "any other op". A sum or an `optional` would make `{0, true}` unrepresentable (read).
- **Dead function** `include/idr/Transforms/StructureLoops.h:98`, `lib/Transforms/StructureLoops/Lowering.cpp:56-60` — `extentsOf` is declared and defined but never called (measured).
- **Stale pass name** `lib/Conversion/Memrefs.cpp:80` — "idr-rc's". No pass has that name; the spec's pipeline has `idr-rc-cells`, `-borrows`, `-place`, `-exclusive`, `-reuse` and `-expand`. AGENTS.md lists this as a "never" (28274bd3) (measured against `spec/Pipeline/Pipeline.idr`).
- **A hand copy of a shared check** `lib/Transforms/Narrow/Narrow.cpp:86-93` — idr-narrow-words writes its own decide-before-apply check (`getCachedParentAnalysis<Ranges>` plus an internal error). Meanwhile `Ranges::decideStep` (`include/idr/Analysis/Ranges.h:53`) exists for `solver::decided`, which nothing calls (see L14) (read).

## L13

- **Stale op name** `include/idr/IR/Numeric/Domain.h:16` — the comment says `idr.int.divs`; the spec names the op `int.div_s` (`spec/Ops/Scalars.idr:35`). Among `idr.*.*` mentions in comments, it is the only one that matches no spec string (measured).

## L14

- **Dead decide-before-apply check** `include/idr/Analysis/Solver/Decision.h:35-49` — `DecisionAnalysis` and `solver::decided` have no caller, and their only candidate consumer checks by hand (L12 above). The check itself tests the pipeline's order at run time, although the generated pipeline fixes that order (measured: `decided(` is used only as `Nodes.cpp:264`'s unrelated member).
- **Dead function** `include/idr/Analysis/Solver/ProgramGraph.h:199`, `lib/Analysis/Solver/ProgramGraph.cpp:202-206` — `Editor::moveInto` has no caller (measured).
- **Dead accessor** `include/idr/Analysis/Solver/Extraction.h:114` — `itemsOf` has no caller (measured).
- **Op ladder** `lib/Analysis/IdentitiesRecord.cpp:164-190` — `Reader::ofResult` chains `dyn_cast` over `CallOp`, `DataConOp`, `NatPredOp` and `BigAddOp`; its comment calls them "the closed set of constructs this question reads, each through its own op". Dispatch over our ops is MLIR's mechanism (an interface), not a hand chain (read).
- **A bool as the walk's phase** `lib/Transforms/EGraph/Elaborate.cpp:103-121` — `Step::expanded` runs a hand post-order. `depthFirst` (`include/idr/Support/Nest.h:30-34`, with `enum class Way { Down, Up }`) is the shared walk C99 names (read).

## L16

- **The D68 growth proof**, including the run-time re-check: in progress.

## L18

- **Shared op shape by duck typing** `lib/Transforms/Defunctionalize/Edits.cpp:73-79` — `labelled` is an unconstrained generic lambda (`[&](auto op)`). It is called on `FnClosureOp` and `LazySuspendOp` and reads `getResult`, `getCalleeAttr` and `getIndexArgs` off both. No interface and no concept states that shared shape (read; the only `](auto op)` lambda in the tree, measured).
- **A bool as the walk's phase** `lib/Transforms/Defunctionalize/Convert.cpp:90-125` — `Visit::expanded` runs a hand post-order, and `fieldSlots` is computed again on each visit. `depthFirst` is the shared walk (read).

## L19

- **Recursion on input depth** `lib/Transforms/Expect/Named.cpp:69-76` — `locationNames` calls itself through `NameLoc` children and the parts of `FusedLoc`, so its depth is the location's nesting. Its comment argues that the walk ends, not that it is bounded (read).

## L21

- **Dead function** `include/idr/Conversion/Runtime.h:164`, `lib/Conversion/RuntimeCells.cpp:79-82` — `Runtime::loadInfo` is never called (measured: two hits).
- **LLVM attribute kinds spelled as text** `lib/Conversion/Lower/Attributes.cpp:52-57` — `effects::Attribute::MustProgress`, `NoFree` and `NoSync` become the literals `"mustprogress"`, `"nofree"` and `"nosync"`, a hand mapping from the effect table to LLVM spellings (read).
- **The program's symbol table built twice in one run** `lib/Conversion/Lower/Functions.cpp:110` and `lib/Conversion/Lower.cpp:259` — `viewsWhereAsked` builds a `SymbolTable` of the program, then idr-lower builds another right after (`Lower.cpp:257-259`). Neither comes from the analysis manager, although other passes keep `SymbolTable` as an analysis (`Narrow.cpp:230`) (read).

## Lanes with no finding

INT, L01, L06, L08, L10, L15, L17 and L20 have no finding in this area. L06, L16, L17 and L20 own no swept file.

## Noted, not counted

- Five `llvm_unreachable` and one `std::unreachable()`, each after a `switch` over every case of a scoped enum: `lib/Driver/Outcome.cpp:62`, `Options.cpp:331`, `Main.cpp:56`, `lib/IR/Layout/Layouts.cpp:382`, `include/idr/Transforms/Counting/Facts.h:61`, `include/idr/IR/Effects/Vocabulary.h:190`.
- Map keys:
  - Pointer-keyed maps that only number nodes into vectors or bitsets: `Expect.h:220`, `Narrow.h:305`, `BufferizeModels.h:79`, `LabelPoints.h:110, 161`, `Extraction.h:100`, `EGraph/Simplify.cpp:95`, `Joins/IdenticalRegions.cpp:43`, `InPlace/Unique.cpp:218`, `UniqueResults.cpp:207`, `StructureLoops/Linalg.cpp:41`.
  - `SetVector<Value>` for upstream's `getUsedValuesDefinedAbove`.
  - Name-keyed maps over LLVM modules across contexts, each with its reason stated (`Driver/StackBound.*`, `LinkRuntime.cpp:85`).

## Counts

| Lane | Findings |
|------|----------|
| L02  | 1 |
| L03  | 2 |
| L04  | 5 |
| L05  | 2 |
| L07  | 1 |
| L09  | 1 |
| L11  | 3 |
| L12  | 5 |
| L13  | 1 |
| L14  | 5 |
| L16  | 1 (in progress) |
| L18  | 2 |
| L19  | 1 |
| L21  | 3 |
| All  | 33 |

**Checked and found done: 50 items, plus nine rules with no hit.**
- **From `sweep.md` (44 of 45 hits done):**
  - R1: all 9 accessors are gone. The `std::get<Alt>` in Counting, Trmc's `index() != 0` and `Flow.cpp`'s `cast<Region *>` all now go through `match`.
  - R7 and R7s: all 21 pointer-keyed maps and sets are gone, or turned into numberings.
  - R9: all 14 bools became enums: `Initial`, `DefKind`, `PieceForm`, `ItemOrList`, `TypeForm`, `GroupIn`, `Made`, `Prelude`; `Reference::tailCall` was deleted.
  - R8 is partial (L12 above).
- **From `traceability-recheck2.md`, 6 of 7 C++ rows done:**
  - D7's `Forms.cpp` list.
  - Function numbering by name at Contify, Demand and Deduplicate (4 sites).
  - C173's stale comment in `Bufferize/Linear.cpp`.
  - D7's Narrow half is partial (above).
- **The nine rules with no hit:**
  - `get_if`, `holds_alternative`, `visit` or `TypeSwitch` outside `Match.h`.
  - A catch-all `match` case: 342 calls scanned; only the refusal test's witnesses at `unittests/Refusals.cpp:165, 176`.
  - A concept that lists ops.
  - `assert`.
  - `std::function`, or a `function_ref` outside an upstream signature.
  - The greedy driver, `canonicalize` or CSE.
  - A header under `lib/`.
  - A unit over 400 lines that is not listed (only `idris-mlir-tblgen.cpp`, which is listed).
  - A per-target macro outside `runtime/Platform/`.
  - (Also, no hand-written `.td` remains outside `Generated/`.)
