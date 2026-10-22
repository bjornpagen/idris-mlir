<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 traceability: decisions C96 to C190

Read from the tree on main at 39a31f8b (2026-10-22) with the working tree
as it stood, read-only, nothing built. "In progress" means the working tree
holds untracked or uncommitted work of the owning lane.

| decision | verdict | where, or what is missing | owner |
|---|---|---|---|
| C96 | Implemented | `lib/Transforms/Tail/Frames.cpp`, `FramesFamily.cpp`, `Continuations.cpp`, `Jumps.cpp`; `answerTypeOf`/`asAnswer`/`fromAnswer` and `FramesPlan.cpp`/`FramesTypes.cpp` gone (working-tree edits continuing) | L10 |
| C97 | Implemented | `lib/IR/Tail.cpp` `endsWithCall`/`verifyOperands`; `Conversion/Frame.{cpp,h}` and `Transforms/Stack/` gone | L10 |
| C98 | Implemented | `lib/Driver/StackBound.cpp` (`DiagnosticInfoStackSize`, red zone); bound reaches the runner in C101's record (`stack_bytes`, `idris_rt.h:276`); `tests/musttail-matrix`; `Support/Stack.h` gone | L11, L19 |
| C99 | Partial | Iterative patches 80-85, 88-93, 97 carried, `std::function` recursions gone; patches 90 and 91 have PINS entries naming `tests/upstream-operation-equivalence-iterative` and `tests/upstream-buffer-type-iterative`, neither exists; op parser/printer, dialect-attribute parameters and `eraseOp` left for stage-1 painting (PINS.md `mlir-recursion`) | L06, L19 |
| C100 | Implemented | `runtime/Alloc/Cells.cpp` (4 GiB-aligned span, `FlatPagemap`); patches 94, 95 with tests; `heapRegion`, `MAP_NORESERVE`, `ensure_init`, `idris_rt_gmp_init` gone | L11 |
| C101 | Implemented | `Spec/Runtime/Endings.idr` (`Ending`, `Exited (Fin 256)`); `runtime/End/End.cpp` `idris_rt_exit`; harness `expected-ending`; old crash/exit entries gone | L11 |
| C102 | Implemented | `#idr.site` (`Spec/Ops/Checks.idr` `siteAttr`, `lib/IR/Ops/Sites.cpp`); `CrashCause` immediate in `Conversion/Runtime.cpp` | L13 |
| C103 | Implemented | `runtime/Platform/Posix/Cgroups.cpp` (`memory.max` up the path, `hierarchical_memory_limit`, `memory.swap.max`) | L11 |
| C104 | Implemented | `proposals/0017-apple-dmp.md` D9 withdrawn (C104) | L11 |
| C105 | Partial | `lin.use`/`lin.enter` roots and `UseModel`/`EnterModel` gone; field read is `to_tensor restrict` (`Emit/Bodies.idr:351`); nothing marks it writable when the scrutinee is `unique deep` (no `writable` setter in `lib/`; `Bufferize/Linear.cpp:15-19` "no grade says a buffer is exclusive yet") | L12 |
| C106 | Implemented | `Emit/Tensors.idr` merge via `collapse_shape`/`expand_shape`; `Recognized.idr` `merge` generating | L16, L12 |
| C107 | Implemented | `lowerToLoopsUsingSCFForOp` in `StructureLoops/StructureLoops.cpp`, `OpsGenerating.cpp`; `Idr_Iteration`/`getIterations` gone | L12 |
| C108 | Implemented | `upstream/27-*/llvm.patch`, `upstream/64-*/llvm.patch`, both tests | L12, L06 |
| C109 | Implemented | `#idr.mutable` (`Spec/Arrays/Memory.idr`); `ArrayUpdateOp::verifyRegions` (`OpsArrays.cpp:139`); `ElementUpdateOp` gone | L12 |
| C110 | Implemented | `include/idr/IR/Numeric/{Domain,Word,Intervals,Arith,Inline}.h` (`SafeDivisor`, `BelowWidth`), included by `runtime/Big/Arithmetic.cpp`; word header sits under `foreign/idr/include`, not `runtime/` | L13 |
| C111 | Partial | Conditions one function each (`Numeric/Inline.h` `Nonzero`/`InBounds`/`InRange`); no `Fin n` seed: `ranges::ofType` (`lib/IR/Ranges.cpp:113`) seeds only nat, big and width | L13, L14 |
| C112 | Partial | Quantity drop fixed (`lazy.delay` has `ResultUsesMaxOf`); `delayOp` is still its own definition beside `captureOp` (`Spec/Closures/Declarations.idr:195`) | L18 |
| C113 | Implemented | `Meaning` sum (`Spec/Core/Op.idr:229`), `FoldsByRuntime` (`IR/Fold.h:132`), `nat.pred`, region `io.unsafe_run`, `platform.os` (named per C158), `buffer.*` memory effects | L13 |
| C114 | Implemented | patches 72, 74 with tests; `Scc.cpp`, `stronglyConnected` gone | L14, L06 |
| C115 | Implemented | `Analysis/Solver/Trace.h` zones; actions in `Support/Actions.h` | L14 |
| C116 | Implemented | `Analysis/Solver/Decision.h` (`decided`, decide/apply/restructure); `PassKind` in `Spec/Pipeline/Pass.idr` | L14 |
| C117 | Implemented | `Analysis/BindingTimes.cpp` flat solve per root (corpus remark comparison needs a build) | L14 |
| C118 | Needs no code | A placement rule; carried by C122 and kin | coordinator |
| C119 | Partial | `include/idr/IR/Quantities.h` `Token` used by `Counting/ReuseAssign.cpp`; `Exclusive` has no production reader (only `unittests/Refusals.cpp:181` calls `asExclusive`) | L15, L07 |
| C120 | Implemented | bool parameters and `DataRemap`/`RunPipeline` gone; `StagedPass` CRTP (`Transforms/Pipeline.h:32`), patch 76 | L15 |
| C121 | Partial | Code side holds (no `matchPin` in code); `audits/p0/design/compile-time-cpp.md` not re-based: T0 still "TableGen, the records" (line 70), `matchPin` at 1223 | coordinator |
| C122 | Implemented | `Translate/Closed.idr` `erasedPosition` reads the fork's `eraseArgs` once (`upstream/fork-erase-args`); `ArgumentAt` (`State.idr:378`) | L16, L17 |
| C123 | Partial | `Template` holds closed content (`Growth/Template.idr:75`); no `Decided` with erased evidence: `Decision` keeps `Holds : p` (`Proof/Growth.idr:44`) and `fitsWithin` builds a unary `LTE` per request (`Proof/Requests.idr`); `readings` map kept (`State.idr:526`) | L16 |
| C124 | Implemented | `Translate/Closed.idr:195` `delayedLets` moves only a `ByElaborator` delay | L16 |
| C125 | Partial | Fork code and PINS `posix-paths` present, `isWindows`/`Volume` gone; no test (no `tests/*` reads a path with `:`) | L17, L19 |
| C126 | Partial | `ITypeOrValue`/`Overlaid` in the fork; the term comparison with stock Idris over prelude, base, `libs/`, fork, frontend and `tests/` is absent (needs a build) | L17 |
| C127 | Implemented | `Core/Unify.idr` `Searched`/`Grown`; `Quoted`/`TooDeep`; "Cycle in search" gone | L17 |
| C128 | Implemented | `delayDepth`, `%search_timeout`, `%foreign_impl`, `--debug-elab-check`, `processTTImpFile` gone | L17 |
| C129 | Partial | `CaseBlock : Name -> Nat -> Name` (`Core/Name.idr:49`); `tests/upstream-patches` never applies the Idris `pull-request.diff`s with `git apply --check` | L17, L19 |
| C130 | Implemented | `--idr-expect-at` (`Driver/Options.cpp`, `Transforms/Expect.h`), `#idr.binder`; `harness/lib/mlir.sh` gone | L19 |
| C131 | Implemented | `harness/Case.idr`, `Facts.idr` read `Spec.Runtime.Endings`; three protocol copies gone | L19 |
| C132 | Implemented | `--emitted` (`Driver/Options.cpp:75`); drawn skip set in `harness/lib/actions.sh`; `tests/actions-skip-programs` gone | L19 |
| C133 | Implemented | `harness/Scale.idr` eight fixtures incl. threads; `tests/scale-*`; `defunc-tag-limit` gone | L19 |
| C134 | Partial | Runner depends on `idris-mlir-spec` only, endings and rules imported; primitives still a hand table (`harness/Prims.idr`, 728 lines, imports no spec module) | L19 |
| C135 | Implemented | `harness/lib/differential.sh` (all optimizations skipped), `harness/Linear.idr`; `Sem.maxCases` gone | L19 |
| C136 | Needs no code | Scheduling of absorbed stages; their code is other decisions' | coordinator |
| C137 | Implemented | `Spec/Core/Admitted.idr`, `Generator/Cpp.idr` (`IdrAdmittedClasses.h.inc`) | L03 |
| C138 | Superseded | Route amended by C177 | L11 |
| C139 | Partial | One decider `tail::decide` (`IR/Tail.cpp`), used by contify, specializer, defunctionalization, TRMC, frames; verifier checks only that a `tail` call is in tail position, never that a call in tail position is `tail` (`IR/Tail.cpp:136, 155-180`); the frontend derives the fact separately (`Emit/Bodies.idr:389`) | L10, L16 |
| C140 | Implemented | `Spec/Lifetimes/Declarations.idr` (openers, `activation`, `lend`, `forget`), `Spec/Lifetimes/Kind.idr` | L05 |
| C141 | Needs no code | Fixed upstream (3d88cd257637), reached by the pin 416f328b | L06 |
| C142 | Implemented | 0017 D9, 0018 D1, 0011 O0 amended | coordinator |
| C143 | Implemented | `GradedType::verify` refuses the bare grade (`lib/IR/Grades.cpp:109-123`) | L05 |
| C144 | Implemented | `Spec/Grades/Hold.idr` (`Counted Unique`, `Scoped Unique`, `Static`), no undecided case | L05 |
| C145 | Implemented | `activation` and `lend` give `view` (`Spec/Lifetimes/Declarations.idr:534, 550`) | L05 |
| C146 | Implemented | `lifetime.reserve` (`Declarations.idr:581`, `IR/Lifetimes/Ops.cpp:239`) | L05 |
| C147 | Implemented | One `Cursor` kind; stack discipline in `IR/Lifetimes/Verify.cpp:220-225` | L05 |
| C148 | Implemented | `Home Nat` (`Kind.idr:25`); `homeSlot` (`Conversion/Lower/Lifetimes.cpp:108`) | L05, L21 |
| C149 | Superseded | By C163, then retired by C165 | L06 |
| C150 | Implemented | `array.read` gives the array back (`Spec/Arrays/Memory.idr`, `Emit/Bodies.idr` `ReadBackF`) | L16, L12 |
| C151 | Needs no code | Measurement upholding D103 | coordinator |
| C152 | Implemented | `array.get` declares `Read Contents` only (`Spec/Arrays/Memory.idr`) | L12 |
| C153 | Implemented | `lib/Transforms/EGraph/` (Build, Nodes, Rules, Simplify, Elaborate) | L14 |
| C154 | Needs no code | A rule; no `Dec` built in `libs/` (grep empty) | L20 |
| C155 | Implemented | `Numeric/Laws.h` (power-of-two, negative shift, char laws), no synthesizer in tree | L13 |
| C156 | Partial | `nodesPerOp = 64` is a literal in the generator (`Generator/Cpp.idr:921`), not a measured constant of the specification's data; measurement waits on stage 1 | L03, L14 |
| C157 | Implemented | No greedy driver or canonicalization pattern in `lib/`, `include/`, spec (grep empty) | L13, L14 |
| C158 | Implemented | Spec mnemonics follow `parts/contracts/mnemonics.md` | L03 |
| C159 | Implemented | `SpineUnique : Writable (Counted Self)` (`Spec/Functions/Parameters.idr:43`), `IR/Func/Values.cpp:146` | L02 |
| C160 | Implemented | `forget`/`reserve` as the derived results (`Spec/Lifetimes/Declarations.idr`) | L05 |
| C161 | Implemented | `count.dup`/`count.drop` take `countedValue` (`Spec/Counting/Declarations.idr:161, 174`) | L05, L07 |
| C162 | Implemented | `!idr.graded` parameters, no grade attribute (grep empty) | L05 |
| C163 | Superseded | Retired by C165 | L06 |
| C164 | In progress | Generator side present (`Spec/Generator/Manifest.idr`); no generated `.td`, Idris `Dialect/Idr.idr` or `foreign/idr/generated.manifest` committed, no regeneration check in `Makefile` | INT, L03 |
| C165 | Implemented | `upstream/78-*` kept as a submission (no `llvm.patch`); README table row | L21, L06 |
| C166 | Implemented | `Spec/Control/Matches.idr` default binds the complement; `Analysis/Ranges.cpp:73` | L09, L16 |
| C167 | Implemented | `DestType::verify` (`IR/Tail/Destinations.cpp:32`), amended by C176 | L10 |
| C168 | Implemented | `runtime/Rc/Rc.h:78` (0 static, no atomic) | L11 |
| C169 | Implemented | `runtime/Strings/Simd.h` final class, patch 98 with test | L11 |
| C170 | Implemented | Amended by C179: `outers` (`Spec/Control/Matches.idr:67`, `Control/Joins.idr`) | L09 |
| C171 | Implemented | Amended by C179: `dest.answer` (`Spec/Tail/Declarations.idr:110`, `Conversion/Lower/Destinations.cpp`) | L10 |
| C172 | Implemented | `tools/bootstrap.sh` `llvm_tree` (stage 1 from the patched copy) | L06 |
| C173 | Partial | Local rule (`InPlace/Unique.cpp`, `raiseClaims`) runs before bufferization (`Spec/Pipeline/Pipeline.idr:567`); bufferization does not read the grade (`Bufferize/Linear.cpp:15-19`; no claim read in `Bufferize/`), so a buffer in a cell is still never writable | L12, L08 |
| C174 | Implemented | `Translate/Choices.idr` closed sum per implementation | L16 |
| C175 | Implemented | `Frontend/Finite.idr:23` semi-naive over the instance table | L16 |
| C176 | Implemented | `!idr.dest<T>` takes graded `T`; `DestWriteOp::verify` (`Destinations.cpp:52`) | L10 |
| C177 | Implemented | `runtime/Alloc/Peaks.cpp`, `FrameBoundExceeded` (`Spec/Runtime/Endings.idr`, `runtime/End`), `tests/runtime-frame-bound` | L11 |
| C178 | Implemented | `include/idr/Support/Footprint.h`; `harness/lib/scale.sh` | L15 |
| C179 | Implemented | Row `dest.answer` (`%r:2`), `outers` one per scoped value | L10, L09 |
| C180 | Implemented | `array.place_copy` (`Spec/Arrays/Memory.idr:305`), `Bufferize.cpp:191, 287` (`memCpyFn`), `Conversion/Movements.cpp:165` | L12, L16 |
| C181 | Implemented | `outers` on `data.con`/`data.field`/`data.reindex` (`Spec/Families/Dialect.idr:627, 674, 742`), `lin.cast` (`Spec/Grades/Declarations.idr:268`) | L05 |
| C182 | Implemented | `outers` ordering stated (`Spec/Control/Matches.idr:70`, `Joins.idr:26`), checked in `IR/Families/Rules.cpp`, `IR/Control/JoinsSyntax.cpp` | L09 |
| C183 | In progress | `compiler/idris/src/Core/TT/Stored.idr` untracked, already imported by `Core/Context.idr`, `Hash.idr`, `Eval.idr` | L17 |
| C184 | Implemented | No header under `foreign/idr/lib/` (find empty) | L19 |
| C185 | Implemented | `InPlace/Rule.cpp:117-127` `boundaryAsks` (`ownBuffers`), `own.adopt` (`Spec/Counting/Declarations.idr:421`) | L08 |
| C186 | Implemented | `Conversion/Lower/Accounts.cpp`; `tests/shipped-accounts` | L21, L19 |
| C187 | Partial | Patch 99 and its PINS entry carried, `idr.func` overrides the edits (`IR/Func/Edits.cpp:157-181`); `tests/upstream-function-interface-edits`, which PINS.md:1203 names, does not exist | L06, L19 |
| C188 | Implemented | Frontend writes no parameter claim (Emit holds `Counted` on parameters); `idr-in-place` writes the boundary grade (`InPlace/Rule.cpp`) | L08, L16 |
| C189 | Implemented | `Transforms/Lifetimes/Decide.cpp:22-49` (`FramedCalls`, members' calls counted), `Counting/Borrows.cpp:24`; Tail working-tree edits continuing (`ComponentLifetimes.cpp` untracked) | L10, L05 |
| C190 | Implemented | `InPlace/Writer.cpp:150` `raiseClaims` after the boundary grade | L08 |

Outside the table: the library build files INT owns still name 91 sources
`foreign/idr/lib` no longer holds (`lib/Transforms/CMakeLists.txt:225-226`
`Tail/FramesPlan.cpp`, `Tail/FramesTypes.cpp`; `lib/IR/CMakeLists.txt:45`
`DataRemap.cpp`), so INT has to rewire them at the integration build (D111).
