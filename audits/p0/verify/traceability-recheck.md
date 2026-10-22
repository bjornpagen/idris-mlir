<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Traceability recheck: the open rows of D, C1 and C2, and C196 to C205

Read from `main` at c0cc4cf8, with the working tree as it stood at
00:58 CDT on 2026-10-22. Lanes were committing and writing while this
was read: HEAD moved from 7a7dd07e to c0cc4cf8, and the rows whose files
those commits or the working tree touched (C4, C25, C52, C105, C173,
C198, C204, C205, D7) were read again at c0cc4cf8. C198 and C205 were
being edited in the working tree as this was finished. Four commits
landed just after (569d1d61 to 3cfef779): L12g and L07h commit what this
report marks uncommitted for C52, C105, C119 and C173 (checked: the
cited lines stand at 3cfef779), and C207 to C209 are outside this check. Nothing was built or
run. Ground, for every row: read, meaning the cited line was seen in the
file. "Uncommitted" marks work present only in the working tree. Paths
are under `foreign/idr/` unless they start with another top-level
directory; `spec/` is `compiler/spec/IdrisMLIR/Spec/`. Owners come from
`ownership.json`.

Not repeated per row: the library CMake lists still name 98 sources that
no longer exist (counted over `lib/CMakeLists.txt` and `lib/*/CMakeLists.txt`),
and `include/idr/IR/Generated/` holds three untracked files (`Families`,
`StageFacts`, `Verdict`) out of the dozen-plus that committed code
includes. `generated.manifest` is absent. Both are INT's (D111).

## 1. Recheck of the rows marked Partial or Missing

| item | was | now | evidence (read), and what remains | owner |
|---|---|---|---|---|
| D7 | Partial | Partial | `TypeSwitch` is gone (0 hits outside `Support/Match.h`'s comment). Op-list ladders remain: `isa<BigSmallOp, BigFromSIntOp, BigFromUIntOp>` at `lib/Transforms/Narrow/Narrow.cpp:142`, and nine arith ops listed for associativity at `lib/Transforms/StructureLoops/Forms.cpp:87`, which should read the spec's `UpAssociative` | L12 |
| D10 | Partial | Partial | `IdrisMLIR/Laws.idr` and the per-compile law run are gone. The run-time re-check of proved bounds remains: `compiler/src/IdrisMLIR/Frontend/Finite.idr:171-191` (`unsound`, `heightWithin`, `sizedWithin`) and `Frontend/Translate/Types.idr:902-908` (`boundsHold`) | L16 |
| D16 | Partial | Partial | No hand `.td` is tracked. The generator's outputs are neither all generated nor committed (see the note above) | INT |
| D44 | Partial | Partial | A0 is committed (31013e5a: interned names, `Core.TT.Stored`). 0011 O1 (token SoA) and O5 (flat parse tree, resolution as interval join) are still owed: the L17c handoff does not claim them, and no fork module imports `mlir-relational` | L17 |
| D46 | Partial | Partial | `compiler/src/IdrisMLIR/Proof/Bound.idr:3-5` still proves Theorem 1 "over a model of what the frontend's sites write", not over `Template`. The run-time re-check is as in D10 | L16 |
| D48 | Partial | Done | `#idr.types` and `!idr.box` have 0 hits outside `sources/notes/`. L06g (9771a679) moved the upstream reproducers to the new syntax | L06, L19 |
| D49 | Partial | Partial | The committed generated files do not exist yet | INT |
| D50 | Partial | Partial | The stale mentions in `Outcome.cpp` and `tests/rules-covered` are gone. `include/idr/IR/CMakeLists.txt:23,27-28` still generates `IdrRules.txt`, `IdrPassRoles.txt` and `IdrPassStages.txt`, and nothing reads them | INT |
| D57 | Partial | Partial | A fired rule still replaces the node with no union (`lib/Transforms/EGraph/Nodes.cpp:207-233`). The interim holds: the replacement meets the replaced node's facts (`:218-219`). This is §4's second owner question | L14 (owner) |
| D67 | Partial | Partial | `generated.manifest` is absent | INT |
| D69 | Partial | Done | O6 is committed: uses are summed in the semiring (`compiler/idris/src/Core/LinearCheck.idr:30-48`, `accumulate (\|+\|)`), and size-change composition is `contract` (`Core/Termination/SizeChange.idr:275-278`). O7's union-find is from e5b39cb2. An uncommitted diff to `LinearCheck.idr` swaps a private `writeFrom` for `mlir-array`'s `fromList` | L17 |
| D71 | Partial | Done | `LArray` and `Linear.Vec` are `InPlaceType` entries (`compiler/src/IdrisMLIR/Registry/Recognized.idr:137-142`, C193). Bufferization reads the cell's grade (`lib/Transforms/Bufferize/Releases.cpp:231`). The claim level is §4's first owner question; the working tree writes C185's `unique deep` (`Releases.cpp:58`, committed by L12g) | L16, L12 |
| C1 | Partial | Done | C196 makes the cycle restriction the decided form: a call on the caller's own cycle lends nothing (`lib/Analysis/Ownership/Borrows.cpp:21-27,157-162`) | L08 |
| C4 | Partial | Partial | The short circuit is committed (c0cc4cf8): `ShortCircuit` combinations at `lib/Transforms/Tail/Accumulate.cpp:11,96-146`. The laws of `big.mul`, `big.and`, `big.or` and `big.xor` (`spec/Ops/Bigs.idr:171-200`) and of `str.append` (`spec/Ops/Strings.idr:68`) are uncommitted. `Identity ""` does not fit `Law`'s `Identity Integer` (`spec/Core/Op.idr:260`), and `laws::identityOf` makes only integer literals (`lib/IR/Dialect.cpp:75-88`), so string concatenation still has no identity reader | L13, L03 |
| C22 | Partial | Partial | `finToNat` and `natToFinLT` are still `IdentityOnLastArgument` rows (`Registry/Faster.idr:99-100`). The frontend writes no `idr.numeral.to_nat` or `of_nat` (0 hits in `compiler/src`), though the ops exist (`spec/Families/Ops.idr:270-312`) | L16 |
| C24 | Partial | Done | C196 amends C24. `io.file_time` takes a file and gives a handle, and one `handle.file_time <field>` reads each of six fields (`spec/Ops/Platform.idr:173-245`; `runtime/Io/FileTimes.cpp:36-65`) | L13, L11 |
| C25 | Partial | Partial | In flight, uncommitted. The writers and `shownOutput` are in `spec/Ops/Strings.idr` and `Bigs.idr`, and `lib/Conversion/Strings.cpp:15,38` includes `idr/IR/Generated/ShownOutput.h.inc`, which does not exist. The runtime has no `idris_rt_io_put_s`, `_u`, `_f64` or `_big` (`runtime/Io/Output.cpp` has only `put_str` and `put_char`) | L13, L11 |
| C32 | Partial | Partial | Patch 77 is carried, but its qualification numbers are not taken (`upstream/77-dataflow-state-storage/README.md:33-36`). This needs a build | L14, L08 |
| C34 | Partial | Done | `Exclusivity` and `Borrows` derive `ReadsAnalyses` (`include/idr/Analysis/Ownership.h:68,129`). No hand-written `isInvalidated` remains in either | L08 |
| C43 | Partial | Partial | The pool now runs on the tools' stack (`lib/Driver/Compile.cpp:170-172`, `include/idr/Driver/Tool.h:92-94`); patches 100 and 101 are carried (d3935eeb). No target entry defines `IDRIS_MLIR_TOOL_STACK_BYTES`, which `Tool.h:42-43` requires. The checks `tests/upstream-mlir-opt-main-thread-pool` and `tests/upstream-thread-pool-thread-start` are untracked | INT, L19 |
| C46 | Partial | Done | `Nodes::State` holds no mutex (`include/idr/Transforms/SpecializeState.h:200-227`), and `chainOf` reads its keys as a set (`lib/Transforms/Specialize/Specialize.cpp:113-116`). The arena keeps its own interning lock (`include/idr/Transforms/Specialize.h:210`), which is not a context lock | L18 |
| C50 | Partial | Partial | The families' bytecode is still hand C++ (`lib/IR/Families/Bytecode.cpp`, `MemberBytecode.cpp`), mirrored by `compiler/src/IdrisMLIR/MLIR/HandEncoding.idr`. Only the families' enums are generated (`Generated/Families.h.inc`, untracked) | L04, L16, L03 |
| C52 | Partial | Done | Committed by L07h (4689d094) just after the read. No `std::visit`, `get_if`, `holds_alternative` or `TypeSwitch` remains in `lib`, `include` or `tools` (the last two, in `Counting/Placement.cpp` and `PlacementWalk.cpp`, are gone) | L07, L15 |
| C53 | Missing | Missing | No `target_precompile_headers` and no `-fno-pch-timestamp` in any CMake list | INT, L15 |
| C57 | Partial | Done | Uncommitted. `artifact_kinds='module objects executable'` (`harness/lib/compile.sh:111`), `prelude.sh` reads the module, and no expected file lists `core` | L19 |
| C75 | Partial | Partial | Emit still forgets guard positions to `Nat` (`compiler/src/IdrisMLIR/Emit/Operations.idr:131`, `map finToNat`) and looks them up with internal errors (`:98-116`). `caseNumber` finds a case by comparing name strings (`:120-125`) | L16 |
| C77 | Partial | Partial | `MLIR.idr:209-216` keeps `typeDialect` and `attrDialect`, string dialect names. The CMake rule lists are as in D50 | L16, INT |
| C78 | Partial | Partial | Three untracked outputs under `Generated/`, and committed code includes many more (for example `Actions.h.inc`, `Rewrites.h.inc`, `Pipeline.h.inc`). No manifest | INT |
| C81 | Partial | Done | 0d858dba: the program verifier builds no `TypeGraph`. The root's check is `layout::componentCount` (`lib/IR/Func/Program.cpp:67-69`), and `holdsNoComponent` has 0 hits. `TypeGraph` survives only as idr-knots' analysis (`lib/Transforms/Ownership/Knots.cpp:22`) | L04 |
| C82 | Partial | Partial | The frontend writes no `idr.index.assume` (0 hits in `compiler/src`). The identity hooks for `replace` and `rewrite__impl` remain (`Registry/Faster.idr:117-119,136`) | L16 |
| C85 | Partial | Done | An element read out of memory is a `Part` or `Lent`, holding no reference, where the row of the code that runs while it is in use overwrites nothing (`include/idr/Transforms/Counting/Placement.h:43-71`, `Overwrites`) | L07 |
| C89 | Missing | Missing | `InPlaceType` only sets `IsInPlace` (`Registry/Entry.idr:423`). Nothing checks "exactly one constructor with a cell": not the registry, not `Frontend/Translate/Types.idr:1179`, not `FamilyVerify.cpp` | L16 |
| C99 | Partial | Partial | The three tests are now committed (`tests/upstream-operation-equivalence-iterative`, `-buffer-type-iterative`). The op parser and printer, attribute parameters and `eraseOp` are left for the stage-1 painting (`PINS.md:546-555`), which needs a build | L06 |
| C105 | Partial | Done | `Unique::Deep` was uncommitted at c0cc4cf8 and is committed by L12g (569d1d61). A `to_tensor restrict` of a field's buffer is marked writable only when the cell claims `bufferClaim = Unique::Deep` (`lib/Transforms/Bufferize/Releases.cpp:58,221-232`). At HEAD the claim is `Self` | L12 |
| C111 | Partial | Done | `ranges::ofType` seeds a numeral with a closed bound at [0, bound] (`lib/IR/Ranges.cpp:119-126`, `numeralBound`, 0d858dba). A `Fin n` with an open `n` is seeded only at ≥ 0, which an interval cannot do better | L13, L04 |
| C112 | Partial | Done | One `captureOp` family covers `fn.closure`, `lazy.suspend` and `lazy.delay`, with `ResultUsesMaxOf` (`spec/Closures/Declarations.idr:216-240,322`) | L18 |
| C119 | Partial | Done | Per C195: the `Exclusive` handle is gone (`asExclusive` has 0 hits). `Token` has `branch` and an N-arm `rejoin` (`include/idr/IR/Quantities.h:44,69,91-112`), used at `lib/Transforms/Counting/ReuseAssign.cpp:134,306` (committed by L07h) | L15, L07 |
| C121 | Partial | Partial | Re-based (fd03cc75): T0 is the specification (`audits/p0/design/compile-time-cpp.md:9,85`). But §2.2's generator model (`:299-367`) and the `matchPin` sketch (`:1233-1245`) remain, and C121 deletes both | coordinator |
| C123 | Partial | Partial | `Decided` with erased evidence exists (`compiler/src/IdrisMLIR/Proof/Growth.idr:51-53`), and `fitsWithin` is gone. `Decision` with `Holds : p` remains (`:43-44,341`), and so does `TS.readings` (`Frontend/Translate/State.idr:530`) | L16 |
| C125 | Partial | Done | The test exists: `tests/frontend-command-line/run:70-87` reads and writes paths holding `:`, relative and absolute | L17, L19 |
| C126 | Partial | Partial | The term comparison with stock Idris over prelude, base, `libs/`, the fork, the frontend and `tests/` is absent. This needs a build | L17 |
| C129 | Partial | Done | `tests/upstream-patches/run:133-149` runs `git apply --check` on each `[Idris2]` `pull-request.diff` | L19 |
| C134 | Partial | Partial | Amended by C197. The runner depends on `idris-mlir-spec` (`harness/harness.ipkg:9`). The builtins are still a hand table that imports no spec module (`harness/Prims.idr`, 728 lines) | L19 |
| C139 | Partial | Done | One decider (`lib/IR/Tail.cpp:111-117`). It is verified both ways: a call in tail position that is not `tail` is an internal error once decided (`:178-213`). The frontend writes every call `nontail` (`compiler/src/IdrisMLIR/Emit/Bodies.idr:421-437`) | L10, L16 |
| C156 | Partial | Partial | `nodesPerOp` is now spec data (`spec/Pipeline/Pipeline.idr:278-285`) but is unmeasured: "holds the engine's first figure" until the stage-1 measurement | L03, L14 |
| C173 | Partial | Done | As C105. A stale comment contradicts the code: `lib/Transforms/Bufferize/Linear.cpp:16-19` says "no grade says a buffer is exclusive yet" | L12, L08 |
| C187 | Partial | Done | `tests/upstream-function-interface-edits` is committed | L06, L19 |

## 2. New decisions, C196 to C205

| item | verdict | evidence (read), and what remains | owner |
|---|---|---|---|
| C196 | Done | File times as in C24's row. Borrows lend nothing around a call on the caller's cycle (`lib/Analysis/Ownership/Borrows.cpp:157-162`) | L13, L08 |
| C197 | Missing | `harness/Prims.idr` keeps its own operation sum (`data Op`, `:321`), its families (`:315`) and its parameter domains (`Domain`, `Params`, `:273-310`). No builtin names a spec op value. `harness/TwoLevels.idr` is deleted in the working tree (uncommitted) | L19 |
| C198 | Partial | In flight, uncommitted. `spec/Ops/Shapes.idr:335-373` marks `exp`, `log`, the trig functions and `powf` `NeverFolded` through a `folding` field that `Admitted` lacks (`spec/Core/Admitted.idr:56-65`; `UpFold` has no definition), and no generator prints the list. The e-graph's reader is written: it skips `Folding::Never` (`lib/Transforms/EGraph/Nodes.cpp:228`, `Rules.cpp:122-134`), reading a `generated::NeverFolded` that nothing generates | L13, L03, L14 |
| C199 | Missing | `compiler/idris/src/Core/Name/Known.idr` (4,992 lines) still spells each identifier four times, kept in step by `roundTrip` and `below` (`:11-13`). There is no list-and-generator and no manifest entry | L17 |
| C200 | Done | `idr::match` refuses a case that takes every type, by probing (`include/idr/Support/Match.h:17-22,59,157,178`). No generic lambda case remains among the `match` calls | L15 |
| C201 | Partial | The pool workers take the runner's computed stack (`Tool.h:92-94`). But `Tool.h:78-79` plans `IDRIS_MLIR_TOOL_STACK_BYTES` alone, the measured depth (`:39-41`), with no outside-code margin added, while programs add `IDRIS_RT_OUTSIDE_STACK_BYTES` (`runtime/Start/Entry.cpp:51-52`). No target entry defines `IDRIS_MLIR_TOOL_STACK_BYTES`, `IDRIS_MLIR_OUTSIDE_STACK_BYTES` or `IDRIS_MLIR_RED_ZONE_BYTES`. The measurement needs stage 1 | L11, INT |
| C202 | Done | An element an upstream op reads keeps its type's grade, and the in-place rule neither raises it nor follows it (`lib/Transforms/InPlace/Chains.cpp:140-147`; `include/idr/Transforms/InPlace/Rule.h:18-20`). A poison is fresh (`lib/IR/FlowOps.cpp:284-286`) | L08 |
| C203 | Done | The frontend writes `NonTail` (`Emit/Bodies.idr:421-437`). `tail::decide` writes `tail` or `modulo_context` (`lib/IR/Tail.cpp:111-117`), run at the first-order stage (`lib/Transforms/Defunctionalize/Pass.cpp:76`). A nontail call that the context rule admits is an internal error once decided (`Tail.cpp:150-160`) | L16, L10, L02 |
| C204 | Done | 1afb0cb2. The lowering turns a word `lit.match` into `scf.index_switch` with the default handed the scrutinee, and a double match into a chain of `cmpf oeq` (`lib/Conversion/Matches.cpp:116-189`). `scf.index_switch` is admitted `PassesOnly` at `Owned` only (`spec/Control/Matches.idr:362-365`). `compiler/src` writes none | L09, L13 |
| C205 | Partial | In flight, uncommitted (all six `EGraph` files edited while this was read). An integer is the one value of its interval (`include/idr/Transforms/EGraph/Engine.h:141-177`, `node::Integer`, `Facts::integer`), turned into an attribute at write-back. An op's fold runs only where no integer is known and makes an attribute only for a constant with no integer form (`lib/Transforms/EGraph/Nodes.cpp:218-243`). Missing: the never-folded list it reads is not generated (C198's row). Committed HEAD still holds the constant as an `Attribute` | L14, L03 |

C206 (045cfc52, `data.reindex`) and C207 to C209 landed during or just
after this read and are outside this check. C208 amends C85; C85's row
already reads the per-op `Overwrites` that C208 keeps.

## 3. What remains, by owning lane

- **INT**: commit the generated outputs and `generated.manifest` (D16,
  D49, D67, C78); stop generating `IdrRules.txt`, `IdrPassRoles.txt` and
  `IdrPassStages.txt` (D50, C77); add the target entries'
  `IDRIS_MLIR_TOOL_STACK_BYTES`, `OUTSIDE_STACK_BYTES` and `RED_ZONE_BYTES`
  (C43, C201); add the precompiled header (C53, with L15); drop the 98
  stale sources from the CMake lists.
- **L16**: drop the run-time growth re-check and prove Theorem 1 over
  `Template` (D10, D46); `numeral.to_nat`/`of_nat` in place of the `Fin`
  identity rows (C22); typed guard positions and case numbers in Emit
  (C75); drop `typeDialect`/`attrDialect` (C77); write `index.assume` and
  drop the `replace`/`rewrite__impl` hooks (C82); check the one-cell
  constructor of an `in_place` family (C89); drop `Decision`/`Holds` and
  `TS.readings` (C123); with L04 and L03, generate the families' bytecode
  (C50).
- **L17**: O1 and O5 (D44); the term comparison (C126, needs a build);
  generate `Known` from one list (C199).
- **L13**: commit the laws, with L03 widening `Identity` past `Integer`
  and an identity reader for strings (C4); finish the show writers, with
  L11 adding the runtime's `io_put_*` (C25); finish `NeverFolded`, with
  L03 adding `Admitted.folding` and generating `NeverFolded` (C198).
- **L14**: commit the integer-valued rewrite graph once its generated
  never-folded list exists (C205); measure patch 77 with L08 (C32) and
  `nodesPerOp` with L03 (C156, stage 1); the union question (D57, owner).
- **L12**: the two op-list ladders (D7); the stale `Linear.cpp:16-19`
  comment (C173).
- **L19**: the builtins on spec op values (C197, C134); commit the C57
  harness edits and the two thread-pool upstream checks (C43).
- **L11**: the tools' stack is the mark plus the outside-code margin
  (C201).
- **L06**: the stage-1 painting of the three recursion families left
  (C99).
- **coordinator**: remove §2.2's generator model and `matchPin` from
  `compile-time-cpp.md` (C121).
