<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Traceability recheck 2: the rows still open at c0cc4cf8, and §6's deletions

Read from `main` while lanes committed, between c6ccc87f and a98d1cd7
(02:04 CDT, 2026-10-22), with the working tree as it stood then. Rows
whose cited files a later commit touched (C4, C22, C25, C75, C77, C82,
C123, C198, D10) were read again at a98d1cd7. Nothing was built or run.
Ground, for every row: read, meaning the cited line was seen in the file
or the count was taken by `git grep` over the tree. "Uncommitted" marks
work present only in the working tree. Paths are under `foreign/idr/`
unless they start with another top-level directory; `spec/` is
`compiler/spec/IdrisMLIR/Spec/`. Owners come from `ownership.json`.

Not repeated per row (INT's, D111):
- `include/idr/IR/Generated/` tracks six files (`Families.h.inc`,
  `StageFacts.h.inc`, `Verdict.h.inc`, `Wire.cpp.inc`,
  `IdrAdmittedArith.td`, `IdrAdmittedBase.td`), each "written by hand as
  the specification prints them" (27b7c5bc, 005b9d6c), not by a specgen
  run; `Wire.cpp.inc` has uncommitted edits. Committed code includes 40
  distinct `Generated/` names, so 34 are absent (among them
  `Rewrites.h.inc`, `Laws.h.inc`, `ShownOutput.h.inc`, `Pipeline.h.inc`,
  `Actions.h.inc`). `generated.manifest` is absent.
- The library CMake lists still name 98 sources that do not exist
  (counted over `lib/CMakeLists.txt` and `lib/*/CMakeLists.txt`, none
  edited since 10-21).
- Outside this check: the checkouts of `third_party/Idris2`, `modular`
  and `simdutf` differ from their committed gitlinks (working tree only).

## 1. The rows the recheck left Partial or Missing

| item | was | now | evidence (read), and what remains | owner |
|---|---|---|---|---|
| D7 | Partial | Partial | Unchanged: `isa<BigSmallOp, BigFromSIntOp, BigFromUIntOp>` at `lib/Transforms/Narrow/Narrow.cpp:142`, and nine arith ops listed at `lib/Transforms/StructureLoops/Forms.cpp:86-87`, which should read the spec's associativity law. (`Narrow/Widths.cpp:47` and `Expect/Vectorized.cpp:23` list a loop's own op and terminator, structure, not counted.) | L12 |
| D10 | Partial | Partial | The run-time re-check stands: `unsound`, `heightWithin`, `sizedWithin` (`compiler/src/IdrisMLIR/Frontend/Finite.idr:171-195`, called at `:216-217`) and `boundsHold` (`Frontend/Translate/Types.idr:929-935`, called at `:1190-1191`) | L16 |
| D16 | Partial | Partial | The two tracked `.td` were written by hand as the spec prints them (005b9d6c); 34 included outputs absent (note above) | INT |
| D44 | Partial | Partial | O1 is done: tokens and their bounds are two columns read by position (`compiler/idris/src/Libraries/Text/Parser/Core.idr:39-60`, f39c2076). O5: C216 (711766b7) rules that the flat parse tree and decoder land now and puts resolution as an interval join to the owner (§4's fourth question). No flat parse tree or decoder exists under `compiler/idris/src/Parser` or `Idris/Parser.idr`, and no fork module imports `mlir-relational` | L17 (owner: resolution) |
| D46 | Partial | Partial | Theorem 1 is stated over `Proof.Template` (`compiler/src/IdrisMLIR/Proof/Bound.idr:3-5,65,86`, be781ef0; more edits uncommitted). The run-time re-check is still there, as in D10 | L16 |
| D49 | Partial | Partial | As D16 | INT |
| D50 | Partial | Partial | `include/idr/IR/CMakeLists.txt:23,27-28` still asks for `IdrRules.txt`, `IdrPassRoles.txt` and `IdrPassStages.txt`. Nothing reads them, and `tools/idris-mlir-tblgen.cpp` no longer has `-gen-rule-list`, `-gen-pass-roles` or `-gen-pass-stages` (0 hits), so the rule names backends that no longer exist | INT |
| D57 | Partial | Partial | Unchanged: `Function::insert` replaces a node by a class, with no union (`lib/Transforms/EGraph/Nodes.cpp:264-295`; `replacedBy` meets the facts, `:274-277`). This is an owner question | L14 (owner) |
| D67 | Partial | Partial | `generated.manifest` is absent. Its printer exists (`spec/Generator/Manifest.idr:37-45`) | INT |
| C4 | Partial | Done | The laws are committed: `big.add` and `big.mul` (`spec/Ops/Bigs.idr:168,172`), the bitwise ops (`:189,195,201`), and `str.append` with `Identity ""` (`spec/Ops/Strings.idr:69`). The identity is a `LawConstant`, an integer or a string (`spec/Core/Op.idr:248,271`), and `laws::identityOf` makes a string's literal (`lib/IR/Dialect.cpp:80-105`). `Laws.h.inc` is absent (INT) | L13, L03 |
| C22 | Partial | Done | `natToFinLT` and `finToNat` are `PureCall numeralOfNatOp` and `numeralToNatOp` (`compiler/src/IdrisMLIR/Registry/Faster.idr:101-102`) | L16 |
| C25 | Partial | Done | Writers beside the shows (`spec/Ops/Strings.idr:96-147`), lowered by `LowerShownOutput` (`lib/Conversion/Strings.cpp:244-270`). The runtime has `idris_rt_io_put_s` and `_u` (`runtime/Strings/Show.cpp:44-46`), `_f64` (`runtime/Doubles/Printing.cpp:132`) and `_big` (`runtime/Big/Digits.cpp:71`). `ShownOutput.h.inc` is absent (INT) | L13, L11 |
| C32 | Partial | Partial | Unchanged: the qualification numbers are not taken (`upstream/77-dataflow-state-storage/README.md:33-36`). Needs a build | L14, L08 |
| C43 | Partial | Partial | Both thread-pool checks are now committed (`tests/upstream-mlir-opt-main-thread-pool`, `tests/upstream-thread-pool-thread-start`). No target entry (`CMakeLists.txt:195-280`) defines `IDRIS_MLIR_TOOL_STACK_BYTES` or `IDRIS_MLIR_TOOL_SIGNAL_BYTES`, which `include/idr/Driver/Tool.h:45-49` require | INT |
| C50 | Partial | Done | `lib/IR/Families/Bytecode.cpp` (67 lines) holds only the builders the printed codecs call (`:3-8`). `MemberBytecode.cpp` and `HandEncoding.idr` are gone. The codecs are `Generated/Wire.cpp.inc` (`lib/IR/Bytecode.cpp:174`), a hand print, with uncommitted edits | L04, L16, L03 |
| C53 | Missing | Missing | No `target_precompile_headers` and no `-fno-pch-timestamp`. `CMakeLists.txt:40-41` says "No target uses a precompiled header, which ccache cannot cache", which contradicts C53 | INT, L15 |
| C75 | Partial | Done | Guards are `List (Guard (Fin i))` over a `Vect i Value` (`compiler/src/IdrisMLIR/Emit/Operations.idr:111-137`). Neither `finToNat` nor `caseNumber` appears in `Emit/` | L16 |
| C77 | Partial | Partial | `typeDialect` is gone, `attrDialect` gives the closed `Dialect` (`compiler/src/IdrisMLIR/MLIR.idr:233-237`), and `tests/dialects-current` is gone. The CMake rules of D50 remain | INT |
| C78 | Partial | Partial | `generate : List (Path, String)` with no IO (`spec/Generator/Outputs.idr:330`). `tests/spec-current` checks the outputs against a fresh tree. The outputs and the manifest are not committed | INT |
| C82 | Partial | Done | No `replace` or `rewrite__impl` hook left in `Registry/`. Emit writes `idr.index.assume` for an erased equality (`compiler/src/IdrisMLIR/Emit/Bodies.idr:723-726`) | L16 |
| C89 | Missing | Done | An `in_place` family needs exactly one constructor with fields, else the `HookShape` refusal (`compiler/src/IdrisMLIR/Frontend/Translate/Types.idr:1211-1221`). The fixture is `tests/hook-in-place-two-constructors`. The check runs where the frontend meets the constructors. The registry's table holds none, so it cannot run when the table is built | L16 |
| C99 | Partial | Partial | Unchanged (`PINS.md:546-555`). Needs the stage-1 painting | L06 |
| C121 | Partial | Done | `audits/p0/design/compile-time-cpp.md:299-303` says §2.2's C++ model was deleted. `matchPin` has 0 hits | coordinator |
| C123 | Partial | Partial | `Decision` with `Holds : p` stands (`compiler/src/IdrisMLIR/Proof/Growth.idr:43-45`), used at `Frontend/Growth/Potential.idr:545-595`. `TS.readings` stands (`Frontend/Translate/State.idr:531`; `Instances.idr:58-74`) | L16 |
| C126 | Partial | Partial | No term comparison with stock Idris in `tests/`. Needs a build | L17 |
| C134 | Partial | Done | The runner depends on the spec alone (`harness/harness.ipkg:7-9`), `Prims.idr` imports the spec's ops (`harness/Prims.idr:28-37`), and no `.idr` of the harness calls `system`. What is left is C197's | L19 |
| C156 | Partial | Partial | `nodesPerOp = 64`, "Not yet measured" (`spec/Pipeline/Pipeline.idr:278-285`). Needs stage 1 | L03, L14 |

Also from the recheck's Done rows: C57's harness edit is committed
(0e5cb41c; `harness/lib/compile.sh:111`), and so is C69's `fromList`
(`compiler/idris/src/Core/LinearCheck.idr:48`). C173's stale comment
stands: `lib/Transforms/Bufferize/Linear.cpp:16-18` "no grade says a
buffer is exclusive yet" (L12).

## 2. The open rows of C196 to C205

| item | was | now | evidence (read), and what remains | owner |
|---|---|---|---|---|
| C197 | Missing | Partial | The table's own operation sum and parameter domains are gone. Each builtin names `DialectOp = OurOp AnyOp \| AdmittedOp Admitted \| Retyped` (`harness/Prims.idr:372`), and its guards (`:432-435`) and host dependence (`computedOf`, `:385-394`) are read from that op. Its operand and result types are still the harness's own `Ty` (`:49-57`; `takes`, `gives` at `:526-527`), not read from the op value as C197 lists them | L19 |
| C198 | Partial | Done | `UpFold` (`spec/Core/Admitted.idr:38`), `Admitted.folding` (`spec/Core/Op.idr:390`), the nine records `NeverFolded` (`spec/Ops/Shapes.idr:340-384`), printed as `NeverFolded` (`spec/Generator/Cpp.idr:1036`), read once by `foldingOf` (`lib/Analysis/Constants.cpp:35-38`), which the e-graph (`lib/Transforms/EGraph/Nodes.cpp:228`) and idr-lower (`lib/Conversion/Lower.cpp:137`) ask. `Rewrites.h.inc` is absent (INT) | L13, L03, L14 |
| C199 | Missing | Partial | There is one list (`compiler/idris/known/Vocabulary.idr`), and knowngen (`known/Generate.idr`) prints `Core/Name/Known.idr` (header `:3-5`) and `Parser/Lexer/Reserved.idr`. The hand proofs are gone. Still missing: nothing runs knowngen (no hit outside `compiler/idris`; `make check` runs only the suite), and no manifest covers the output, though the header says `make check` regenerates it | L17, L19, INT |
| C201 | Partial | Partial | The runner adds `IDRIS_RT_OUTSIDE_STACK_BYTES` to every plan, the tools' included (`runtime/Start/Runner.cpp:20-26,111-113`, 6d6abccf). No target entry defines `IDRIS_MLIR_OUTSIDE_STACK_BYTES` (`runtime/CMakeLists.txt:212`), `IDRIS_MLIR_TOOL_STACK_BYTES` or `IDRIS_MLIR_RED_ZONE_BYTES` (`lib/Driver/StackBound.cpp:34-35`). The measurement needs stage 1 | INT, L11 |
| C205 | Partial | Done | Committed (7ab6d805, 15878a4b): `node::Integer` (`include/idr/Transforms/EGraph/Engine.h:145-150`), `Facts::integer` (`:173`), and `factsOf` asks for no fold where an integer is known or the op is never folded (`lib/Transforms/EGraph/Nodes.cpp:215-243`). `Rewrites.h.inc` is absent (INT) | L14, L03 |

## 3. §6, what goes: references left in the tree

Searched with `git grep --untracked` outside `audits/`, `proposals/`,
`sources/` and `third_party/`. "Stale CMake" means the file is gone and
only the CMake lists of the note above still name it. Items no symbol
names (the grade's free functions, the 38 hand folders, the marker
traits, `Classes`, Placement's per-region scans, Reuses' simulated body,
the second exclusivity solve, the poison yields, the uniqueness branches,
the per-site crash strings, the NULL and odd-bit tests, the five erasure
readers, the Idris printers of our types, `merge`'s identity entry) were
not checked.

| area | item | remains? where |
|---|---|---|
| Effects | readings besides the one API | None found: no `IOResource`, `DoesIO`, `hasEffect<`, `isMemoryEffectFree` or `wouldOpBeTriviallyDead` in `foreign/`. L02 §1.4's list was not rechecked name by name |
| Types, ops | `ValueFacts`' hand answers | Gone: printed from the spec (`spec/Generator/Ods.idr:690-693`). Only the builtin types' external models remain (`lib/IR/ValueFacts.cpp:18-36`) |
| | `own.adopt`, `own.give` def-use verifiers | Gone: `OwnGiveOp::verify` checks its own types alone (`lib/IR/Counting/Ops.cpp:183-190`) |
| | `#idr.types`, `MutableType`, sealing, `Declarations`, `!idr.box`, `Idr_SumKind`, `Idr_CtorRole`, `tag` attributes, enclosing-match walks | 0 hits |
| | `DataRemap`, `DataBody.cpp`, `Fit.cpp` | Stale CMake (`lib/IR/CMakeLists.txt:30,45,80`). Prose in `tools/lanes/README.md:77` (L06) |
| | old grade and lifetime names | `!idr.q`, `idr.borrow`, `idr.frame` have 0 hits. `README.md:25-26` still says `!idr.lin` and `!idr.own` (INT) |
| Analyses | `CallCycles`, `Recursion`, `Scc.cpp`, Returned's solve | Stale CMake (`lib/Analysis/CMakeLists.txt:7,22`; `lib/Support/CMakeLists.txt:7`; `lib/Transforms/CMakeLists.txt:232-233`) |
| | `MonotoneWorklist`, `FiniteLattice`, `lib/Analysis/Effects.cpp` | 0 hits |
| | function numbering by name | Remains: `DenseMap<StringAttr, unsigned>` over functions at `lib/Transforms/Optimize/Contify.cpp:130,207`, `Optimize/Demand.cpp:52` (beside the `FunctionId`s it is given, `:49`) and `Deduplicate/Deduplicate.cpp:250` (L18) |
| Counting | `Demand.cpp`, `Uses.cpp`, `Take.cpp`, `Owned*.cpp`, Reshape | Stale CMake (`lib/Transforms/CMakeLists.txt:97,194`; `lib/Analysis/CMakeLists.txt:14`; `lib/IR/CMakeLists.txt:57-59`). `Optimize/Demand.cpp` and `Verify/Uses.cpp` are other files |
| | `unknownFrom`, `givesExclusive`, `copyable`, `madeStatic`; `idr-rc-stack` | 0 hits. `isStatic` at `lib/Transforms/Specialize/Consumer.cpp:150` reads the hold, a different function. `idr-rc-stack` appears only in a CMake comment (`lib/Transforms/CMakeLists.txt:93`) |
| Control flow | `Tail/Loop.cpp`, `Tail/WhileDo.cpp`, `Frame.cpp` | Stale CMake (`lib/Transforms/CMakeLists.txt:230-231`; `lib/CMakeLists.txt:44`) |
| Lowering, runtime | `Fields` table, `heapRegion`, 4 GiB reservation, `LowerDrop`'s token branch, `Status`, `idris-mlir:` prefix, live-cell counter, stack bit | `Conversion/Fields.cpp`: stale CMake (`lib/CMakeLists.txt:29`). Only the 4 GiB alignment is left, with nothing reserved (`runtime/Alloc/Cells.cpp:35-44`). `LowerDrop` has no branch (`lib/Conversion/Lower/Counting.cpp:70-83`). The rest have 0 hits |
| Simplification | greedy driver, `canonicalize`, CSE, `getCanonicalizationPatterns`, `Canon/` | 0 hits in `foreign/`, `compiler/`, `tools/` and `harness/`. `Canon/*.cpp`: stale CMake (`lib/IR/CMakeLists.txt:61-68`) |
| Frontend | the fork's `WithBounds` flag | 0 hits for `isIrrelevant` |
| Arrays | `Nests.cpp`; `GeneratingOpInterface`, `Idr_Iteration`, `TabulateIOOp`, `TransposeOp`, `ElementUpdateOp`, `StoreModel`, `HeapReadModel`, `UseModel`, `heldType` | `Nests.cpp`: stale CMake (`lib/Transforms/CMakeLists.txt:341`). The rest have 0 hits, apart from the admitted `linalg.transpose` (`spec/Arrays/Declarations.idr:64`) and a lambda parameter named `heldType` (`lib/Conversion/StaticData.cpp:87`) |
| Idris side | `Translate/Forced.idr`, `idr.refusals`, `Registered.Newtype`, `Facts.terminating`, decimal doubles | 0 hits (doubles cross as bits, `compiler/src/IdrisMLIR/MLIR/Bytecode.idr:504-525`) |
| | `delayedLets`' blanket move | Gone: it moves a `let` only around a `ByElaborator` delay (`Frontend/Translate/Closed.idr:195-198`) |
| | `Finite.heightWithin` and kin | **Remain** (row D10) |
| | string-keyed maps | **Remain**, not judged one by one: `Emit/Closures.idr:101`, `Frontend/Translate/Keys.idr:164`, `MLIR/Bytecode.idr:661` (L16) |
| Fork | the run-time tree, `PartialEval.idr`, the timer, the count pragmas, Windows paths | 0 hits in `compiler/idris/src` (`mkRunTime`, `PartialEval`, `startTimer`, `search_timeout`, a `depth` pragma, `isWindows`, `Volume`) |
| Process | the pipeline order held twice | Gone: `lib/Transforms/Pipeline.cpp:24` reads `Generated/Pipeline.h.inc`, which is absent (INT) |
| | pass names in tests | 35 RUN lines in 24 files name `--idr-expect`, `--idr-contracts`, `--idr-pipeline=to/from` and `--idr-target`: test APIs and stage entry points, not transformation passes |
| | `remove-dead-values` registration; patches 06, 28, 63; the bench's `ulimit -s`; `defunc-tag-limit` | Gone. 06, 28 and 63 are kept as submissions (no `.patch`; `PINS.md:84-95`) |
| | the "1 MiB" test comments | **One remains**: `tests/tail-loop-deep/Prog.idr:3-4` (L19) |
| | the toolchain's assertions; our `assert` | Off at `tools/bootstrap.sh:946,1051,1175`, and no `assert(` in `foreign/` or `runtime/`. **But** `tests/llvm-bootstrap/run:6,21` and `expected:5` still expect `LLVM_ENABLE_ASSERTIONS ON` (L19) |

## 4. What remains, by owning lane

- **INT**: commit the generated outputs from a specgen run, with
  `generated.manifest` (D16, D49, D67, C78, and the absent
  `Rewrites`, `Laws`, `ShownOutput` and `Pipeline` includes of C4, C25,
  C198, C205); drop the three `.txt` rules (D50, C77); give the target
  entries the four stack sizes (C43, C201); add the precompiled header and
  rewrite `CMakeLists.txt:40-41` (C53, with L15); drop the 98 stale
  sources; `README.md:25-26`.
- **L16**: drop the run-time growth re-check (D10, D46); drop `Decision`
  and `TS.readings` (C123); the string-keyed maps (§6).
- **L17**: the flat parse tree and decoder (D44, C216); the term
  comparison (C126, needs a build); a check and a manifest entry for
  knowngen, with L19 and INT (C199).
- **L18**: function numbering by name in Contify, Demand and Deduplicate
  (§6).
- **L12**: the two op-list ladders (D7); the stale `Linear.cpp:16-18`
  comment (C173).
- **L19**: the builtins' types from the op value (C197);
  `tests/llvm-bootstrap` still expects assertions on; the "1 MiB" comment
  in `tests/tail-loop-deep`.
- **L14**: patch 77's numbers (C32, with L08) and `nodesPerOp` (C156, with
  L03), both at stage 1; the union (D57, owner).
- **L11**: the stage-1 measurement of the outside-code margin (C201).
- **L06**: the stage-1 painting (C99); `DataRemap` in
  `tools/lanes/README.md:77`.
- **Owner**: D57's union; §4's fourth question (O5's resolution).
